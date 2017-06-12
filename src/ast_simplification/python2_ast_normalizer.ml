module Simplified = Python2_simplified_ast;;
module Normalized = Python2_normalized_ast;;
open Uid_generation;;

let name_counter = ref 0;;
let use_shortened_names = ref false;;

let gen_unique_name _ =
  let count = !name_counter in
  name_counter := count + 1;
  let prefix = if !use_shortened_names
    then
      "$norm"
    else
      "$normalized_unique_name_"
  in prefix ^ string_of_int count
;;

let reset_unique_name () = name_counter := 0;;
let toggle_short_names (b : bool) = use_shortened_names := b;;

let map_and_concat (func : 'a -> 'b list) (lst : 'a list) =
  List.concat (List.map func lst)
;;

let normalize_option func o =
  match o with
  | None -> None
  | Some(x) -> Some(func x)
;;

let update_uid ctx annot (e : Normalized.annotated_sexpr) =
  let open Normalized in
  {
    uid = get_next_uid ctx annot;
    exception_target = e.exception_target;
    multi = e.multi;
    body = e.body;
  }
;;

let update_option_uid ctx annot (opt: Normalized.annotated_sexpr option) =
  match opt with
  | None -> None
  | Some(e) -> Some(update_uid ctx annot e)
;;

let id_of_name (n : Normalized.annotated_sexpr) =
  let open Normalized in
  match n.body with
  | Normalized.Name (id) -> id
  | _ -> failwith "Can only extract id from names"
;;

(* Given a uid and an annotated_cexpr, assigns that expr to a new, unique name.
   Returns the assignment statement (in a list) and the name used *)
let gen_normalized_assignment ctx annot
    (e : Normalized.annotated_cexpr) =
  let open Normalized in
  let u = get_next_uid ctx annot in
  let name = gen_unique_name u in
  let assignment = {
    uid = u;
    exception_target = e.exception_target;
    multi = e.multi;
    body = Assign(name, e);
  }
  in
  [assignment], name
;;

let create_annotation_from_stmt ctx exception_target in_loop
    (s : 'a Simplified.stmt) (e : 'b) =
  {
    Normalized.uid = get_next_uid ctx (Simplified.extract_stmt_annot s);
    exception_target = exception_target;
    multi = in_loop;
    body = e;
  }
;;

let create_annotation_from_expr ctx exception_target in_loop
    (s : 'a Simplified.expr) (e : 'b) =
  {
    Normalized.uid = get_next_uid ctx (Simplified.extract_expr_annot s);
    exception_target = exception_target;
    multi = in_loop;
    body = e;
  }
;;

(* Most normalize fuctions return a list of statements and the name of the
   variable the last statement bound to. This means that apply List.map to them
   gives a list of tuples; this extracts them into two separate lists. *)
let normalize_list normalize_func lst =
  let normalized_list = List.map normalize_func lst in
  let extract
      (tup1 : 'a list * 'b )
      (tup2 : 'a list * 'b list)
    : 'a list * 'b list =
    (fst tup1 @ fst tup2, (snd tup1)::(snd tup2)) in
  let bindings, results =
    List.fold_right extract normalized_list ([], []) in
  bindings, results
;;

let rec normalize_modl ctx m : Normalized.modl =
  match m with
  | Simplified.Module (body, annot) ->
    Normalized.Module(map_and_concat (normalize_stmt ctx None) body, get_next_uid ctx annot)

(* We need some additional arguments when we're inside a loop,
   so that Break and Continue know what to do. These are only neded in that
   special case, though, so it's convenient to hide them in other cases. *)
and normalize_stmt ctx e s = normalize_stmt_full ctx None None e s

and normalize_stmt_full
    ctx
    loop_start_uid
    loop_end_uid
    exception_target
    (s : 'a Simplified.stmt)
  : Normalized.annotated_stmt list =
  let in_loop = (loop_start_uid != None) in
  let annotate_stmt e : Normalized.annotated_stmt =
    create_annotation_from_stmt ctx exception_target in_loop s e in
  let annotate_cexpr e : Normalized.annotated_cexpr =
    create_annotation_from_stmt ctx exception_target in_loop s e in
  let annotate_sexpr e : Normalized.annotated_sexpr =
    create_annotation_from_stmt ctx exception_target in_loop s e in
  match s with
  | Simplified.FunctionDef (func_name, args, body, _)->
    (* Hopefully the args are just names so this won't do anything *)
    let normalized_body =
      map_and_concat (normalize_stmt ctx exception_target) body in
    let annotated = annotate_stmt @@
      Normalized.FunctionDef(func_name, args, normalized_body)
    in
    [annotated]

  | Simplified.Return (value, _) ->
    begin
      match value with
      | None ->
        [annotate_stmt @@ Normalized.Return(None)]
      | Some(x) ->
        let bindings, result = normalize_expr ctx in_loop exception_target x in
        bindings @
        [annotate_stmt @@ Normalized.Return(Some(result))]
    end


  | Simplified.Assign (target, value, annot) ->
    let value_bindings, value_result = normalize_expr ctx in_loop exception_target value in
    let assign = annotate_stmt @@
      Normalized.Assign(
        target,
        annotate_cexpr @@ Normalized.SimpleExpr(update_uid ctx annot value_result)
      )
    in
    value_bindings @ [assign]

  | Simplified.Print (dest, values, nl, annot) ->
    let dest_bindings, dest_result = normalize_expr_option ctx in_loop exception_target dest in
    let value_bindings, value_results = normalize_expr_list ctx in_loop exception_target values in
    let bindings = dest_bindings @ value_bindings in
    let print = annotate_stmt @@
      Normalized.Print(update_option_uid ctx annot dest_result,
                       List.map (update_uid ctx annot) value_results,
                       nl)
    in
    bindings @ [print]

  | Simplified.While (test, body, annot) ->
    let test_bindings, test_name =
      normalize_expr ctx in_loop exception_target test
    in
    let test_bool_binding, test_bool_name =
      gen_normalized_assignment ctx annot @@
      annotate_cexpr @@
      Normalized.Call(
        annotate_sexpr @@ Normalized.Literal(Normalized.Builtin(Normalized.Builtin_bool)),
        [update_uid ctx annot test_name])
    in

    let open Normalized in
    let start_stmt = annotate_stmt @@ Normalized.Pass in
    let start_uid = start_stmt.uid in (* Start label *)
    let end_stmt = annotate_stmt @@ Normalized.Pass in
    let end_uid = end_stmt.uid in (* End label *)
    let normalized_body =
      (map_and_concat
         (normalize_stmt_full ctx
            (Some(start_uid))
            (Some(end_uid))
            exception_target)
         body)
    in
    let run_test = annotate_stmt @@
      Normalized.GotoIfNot(annotate_sexpr @@ Normalized.Name(test_bool_name),
                           end_uid)
    in
    let end_stmts =
      [
        annotate_stmt @@ Normalized.Goto(start_uid);
        end_stmt;
      ] in
    [start_stmt] @
    test_bindings @
    test_bool_binding @
    [run_test] @
    normalized_body @
    end_stmts

  (* Turn "if test: <body> else: <orelse>" into
     "if not test: goto orelse
     <body>
     goto end
     label orelse
     <orelse>
     label end"
  *)
  | Simplified.If (test, body, orelse, annot) ->
    let test_bindings, test_name =
      normalize_expr ctx in_loop exception_target test in
    let normalized_body =
      map_and_concat (normalize_stmt ctx exception_target) body in
    let normalized_orelse =
      map_and_concat (normalize_stmt ctx exception_target) orelse in

    let test_bool_binding, test_bool_name =
      gen_normalized_assignment ctx annot @@
      annotate_cexpr @@
      Normalized.Call(
        annotate_sexpr @@
        Normalized.Literal(Normalized.Builtin(Normalized.Builtin_bool)),
        [update_uid ctx annot test_name])
    in
    let end_label = annotate_stmt @@ Normalized.Pass in
    let open Normalized in
    let end_uid = end_label.uid in
    let goto_end_label = annotate_stmt @@ Normalized.Goto(end_uid) in
    let orelse_label = annotate_stmt @@ Normalized.Pass in
    let orelse_uid = orelse_label.uid in

    test_bindings @
    test_bool_binding @
    [annotate_stmt @@
     Normalized.GotoIfNot(
       annotate_sexpr @@ Normalized.Name(test_bool_name),
       orelse_uid)] @
    normalized_body @
    [
      goto_end_label;
      orelse_label
    ] @
    normalized_orelse @
    [end_label]

  | Simplified.Raise (value, annot) ->
    let value_binding, value_result = normalize_expr ctx in_loop exception_target value in
    value_binding @
    [annotate_stmt @@ Normalized.Raise(update_uid ctx annot value_result)]

  | Simplified.TryExcept (body, handlers, annot) ->
    let open Normalized in
    let handler_start_stmt = annotate_stmt Normalized.Pass in
    let handler_start_uid = handler_start_stmt.uid in
    let handler_end_stmt = annotate_stmt Normalized.Pass in
    let handler_end_uid = handler_end_stmt.uid in
    let normalized_body =
      map_and_concat (normalize_stmt ctx (Some(handler_start_uid))) body in
    let exception_name = gen_unique_name annot in
    let catch = annotate_stmt @@ Normalized.Catch(exception_name) in
    let rec handlers_to_simplified_if handler_list =
      match handler_list with
      | [] -> (* If we run out of handlers, re-raise the current exception *)
        Simplified.Raise(Simplified.Name(exception_name, annot), annot)

      | Simplified.ExceptHandler(typ, name, body, annot)::rest ->
        let if_test = (* Check if the exception matches this type *)
          match typ with
          | None ->
            Simplified.Bool(true, annot)
          | Some(exp) ->
            Simplified.Compare(
              Simplified.Call(
                Simplified.Builtin(Simplified.Builtin_type, annot),
                [Simplified.Name(exception_name, annot)],
                annot),
              [Simplified.Eq],
              [exp],
              annot)
        in
        let bind_exception =
          (* Bind the exception to the given name, if we have one *)
          match name with
          | None -> []
          | Some(id) ->
            [Simplified.Assign(
                id,
                Simplified.Name(exception_name, annot),
                annot)]
        in
        Simplified.If(
          if_test,
          bind_exception @ body,
          [
            handlers_to_simplified_if rest
          ],
          annot)
    in (* End handler_to_if definition *)
    let normalized_handlers =
      (normalize_stmt ctx exception_target)
        (handlers_to_simplified_if handlers)
    in
    let handler_body =
      [handler_start_stmt; catch] @
      normalized_handlers @
      [handler_end_stmt]
    in
    normalized_body @
    [annotate_stmt @@ Normalized.Goto(handler_end_uid)] @
    handler_body

  | Simplified.Pass _ ->
    [annotate_stmt @@ Normalized.Pass]

  | Simplified.Break _ ->
    begin
      match loop_end_uid with
      | None -> failwith "'break' outside loop"
      | Some(u) -> [annotate_stmt @@ Normalized.Goto(u)]
    end

  | Simplified.Continue _ ->
    begin
      match loop_start_uid with
      | None -> failwith "'continue' not properly in loop"
      | Some(u) -> [annotate_stmt @@ Normalized.Goto(u)]
    end

  | Simplified.Expr (e, annot) ->
    let bindings, result = normalize_expr ctx in_loop exception_target e in
    bindings @
    [annotate_stmt @@ Normalized.SimpleExprStmt(update_uid ctx annot result)]

(* Given a simplified expr, returns a list of statements, corresponding to
   the assignments necessary to compute it, and the name of the final
   variable that was bound *)
and normalize_expr
    ctx
    (in_loop : bool)
    exception_target
    (e : 'a Simplified.expr)
  : Normalized.annotated_stmt list * Normalized.annotated_sexpr =
  let annotate_stmt ex : Normalized.annotated_stmt =
    create_annotation_from_expr ctx exception_target in_loop e ex in
  let annotate_cexpr ex : Normalized.annotated_cexpr =
    create_annotation_from_expr ctx exception_target in_loop e ex in
  let annotate_sexpr ex : Normalized.annotated_sexpr =
    create_annotation_from_expr ctx exception_target in_loop e ex in
  match e with
  (* BoolOps are a tricky case because of short-circuiting. We need to
     make sure that when we evaluate "a and False and b", b is never
     evaluated, etc.

     We do this by iteratively breaking down the statements like so:
     "a and b and c and ..." turns into

     "if a then (b and c and ...) else a", except we make sure that
     a is only evaluated once by storing a in a tmp variable after it's
     evaluated.

     To avoid duplicate code, we construct a simplified IfExp to represent
     the above code, then recursively simplify that.
  *)
  | Simplified.BoolOp (op, operands, annot) ->
    begin
      match operands with
      | [] -> failwith "No arguments to BoolOp"
      | hd::[] -> normalize_expr ctx in_loop exception_target hd
      | hd::tl ->
        let test_bindings, test_result =
          (normalize_expr ctx in_loop exception_target hd) in
        let tmp_name = gen_unique_name annot in
        let tmp_binding =
          annotate_stmt @@
          Normalized.Assign(tmp_name,
                            annotate_cexpr @@
                            Normalized.SimpleExpr(update_uid ctx annot test_result))
        in
        let if_exp =
          begin
            match op with
            | Simplified.And ->
              Simplified.IfExp(
                Simplified.Name(tmp_name, annot),
                Simplified.BoolOp (op, tl, annot),
                Simplified.Name(tmp_name, annot),
                annot)
            | Simplified.Or ->
              Simplified.IfExp(
                Simplified.Name(tmp_name, annot),
                Simplified.Name(tmp_name, annot),
                Simplified.BoolOp (op, tl, annot),
                annot)
          end
        in
        let bindings, result =
          normalize_expr ctx in_loop exception_target if_exp
        in
        test_bindings @ [tmp_binding] @ bindings,
        result

    end

  | Simplified.IfExp (test, body, orelse, annot) ->
    (* Python allows expressions like x = 1 if test else 0. Of course,
       only the relevant branch is executed, so we can't simply evaluate both
       beforehand. But in order to be on the right-hand-side of an assignment,
       the expression must be no more complicated than a compound_expr. In
       particular, the expression can't be an assignment.

       So to evaluate x = y if test else z, we first create an if _statement_
       and then use the results of that.
       if test:
         # evaluate and bind tmp = y
       else:
         # evaluate and bind tmp = z
       x = tmp.

       We need to use different variables for test1 and test2 to preserve
       the guarantee that every variable is bound at most once. This means
       that one branch of the if _expression_ will always result in an
       unbound variable error. It is guaranteed that this is the branch we
       do not run, but this still makes me sad.
    *)
    let tmp_name = gen_unique_name annot in
    let test_bindings, test_result = normalize_expr ctx in_loop exception_target test in
    let test_bool_binding, test_bool_name =
      gen_normalized_assignment ctx annot @@
      annotate_cexpr @@
      Normalized.Call(
        annotate_sexpr @@
        Normalized.Literal(Normalized.Builtin(Normalized.Builtin_bool)),
        [update_uid ctx annot test_result])
    in
    let body_bindings, body_result = normalize_expr ctx in_loop exception_target body in
    let body_bindings_full =
      body_bindings @ [
        annotate_stmt @@
        Normalized.Assign(tmp_name,
                          annotate_cexpr @@ Normalized.SimpleExpr(update_uid ctx annot body_result))
      ] in
    let orelse_bindings, orelse_result = normalize_expr ctx in_loop exception_target orelse in
    let orelse_bindings_full =
      orelse_bindings @ [
        annotate_stmt @@
        Normalized.Assign(tmp_name,
                          annotate_cexpr @@ Normalized.SimpleExpr(update_uid ctx annot orelse_result))
      ] in
    let open Normalized in
    let end_stmt = annotate_stmt @@ Normalized.Pass in
    let end_uid = end_stmt.uid in
    let goto_end_stmt = annotate_stmt @@ Normalized.Goto(end_uid) in
    let orelse_stmt = annotate_stmt @@ Normalized.Pass in
    let orelse_uid = orelse_stmt.uid in

    let run_test = annotate_stmt @@
      Normalized.GotoIfNot(
        annotate_sexpr @@ Normalized.Name(test_bool_name),
        orelse_uid)
    in

    test_bindings @
    test_bool_binding @
    [run_test] @
    body_bindings_full @
    [
      goto_end_stmt;
      orelse_stmt;
    ] @
    orelse_bindings_full @
    [end_stmt],
    annotate_sexpr @@ Normalized.Name(tmp_name)

  | Simplified.Compare (left, ops, comparators, annot) ->
    (* "x < y < z" is equivalent to "x < y and y < z", except y is only
       evaluated once. We treat compare in almost exactly the same way
       as we treat boolean operators.

       Specifically, we turn "x < y < z < ..."

       into

       tmp1 = x
       tmp2 = y
       tmp3 = tmp1.__lt__(y)
       if tmp3 then (tmp2 < z < ...) else tmp3*)
    let left_bindings, left_result = normalize_expr ctx in_loop exception_target left in
    begin
      match ops with
      | [] -> failwith "No operation given to comparison"
      | hd::tl ->
        let right_bindings, right_result =
          normalize_expr ctx in_loop exception_target (List.hd comparators) in
        let cmp_func_bindings, cmp_func_result =
          gen_normalized_assignment ctx annot @@
          annotate_cexpr @@
          Normalized.Attribute(left_result, normalize_cmpop hd)
        in
        let cmp_bindings, cmp_result =
          gen_normalized_assignment ctx annot @@
          annotate_cexpr @@
          Normalized.Call(annotate_sexpr @@ Normalized.Name(cmp_func_result),
                          [right_result])
        in
        let all_bindings = left_bindings @
                           right_bindings @
                           cmp_func_bindings @
                           cmp_bindings
        in
        begin
          match tl with
          | [] -> all_bindings, annotate_sexpr @@ Normalized.Name(cmp_result)
          | _ ->
            let if_exp =
              Simplified.IfExp(
                Simplified.Name(cmp_result, annot),
                Simplified.Compare(Simplified.Name(id_of_name right_result, annot),
                                   tl,
                                   List.tl comparators,
                                   annot),
                Simplified.Name(cmp_result, annot),
                annot)
            in
            let bindings, result = normalize_expr ctx in_loop exception_target if_exp in
            all_bindings @ bindings, result
        end
    end

  | Simplified.Call (func, args, annot) ->
    let func_bindings, func_name = normalize_expr ctx in_loop exception_target func in
    let arg_bindings, arg_names = normalize_expr_list ctx in_loop exception_target args in
    let assignment, name = gen_normalized_assignment ctx annot @@
      annotate_cexpr @@
      Normalized.Call(update_uid ctx annot func_name,
                      List.map (update_uid ctx annot) arg_names) in
    let bindings = func_bindings @ arg_bindings @ assignment in
    bindings, annotate_sexpr @@ Normalized.Name(name)

  | Simplified.Num (n, _) ->
    ([],
     annotate_sexpr @@ Normalized.Literal(Normalized.Num(normalize_number n)))

  | Simplified.Str (s, _) ->
    ([],
     annotate_sexpr @@ Normalized.Literal(Normalized.Str(normalize_str s)))

  | Simplified.Bool (b, _) ->
    ([],
     annotate_sexpr @@ Normalized.Literal(Normalized.Bool(b)))

  | Simplified.Builtin (b, _) ->
    ([],
     annotate_sexpr @@ Normalized.Literal(Normalized.Builtin(normalize_builtin b)))

  | Simplified.Attribute (obj, attr, annot) ->
    let obj_bindings, obj_result = normalize_expr ctx in_loop exception_target obj in
    let assignment, result = gen_normalized_assignment ctx annot @@
      annotate_cexpr @@
      Normalized.Attribute(update_uid ctx annot obj_result, attr) in
    obj_bindings @ assignment, annotate_sexpr @@ Normalized.Name(result)

  | Simplified.Name (id, _) ->
    ([],
     annotate_sexpr @@ Normalized.Name(id))

  | Simplified.List (elts, annot) ->
    let bindings, results = normalize_expr_list ctx in_loop exception_target elts in
    let assignment, name =
      gen_normalized_assignment ctx annot @@
      annotate_cexpr @@ Normalized.List(List.map (update_uid ctx annot) results) in
    bindings @ assignment, annotate_sexpr @@ Normalized.Name(name)

  | Simplified.Tuple (elts, annot) ->
    let bindings, results = normalize_expr_list ctx in_loop exception_target elts in
    let assignment, name =
      gen_normalized_assignment ctx annot @@
      annotate_cexpr @@ Normalized.Tuple(List.map (update_uid ctx annot) results) in
    bindings @ assignment, annotate_sexpr @@ Normalized.Name(name)

(* Given a list of exprs, returns a list containing all of their
   bindings and a list containing all of the relevant variable names *)
and normalize_expr_list ctx in_loop exception_target (lst : 'a Simplified.expr list) =
  normalize_list (normalize_expr ctx in_loop exception_target) lst

and normalize_expr_option ctx in_loop exception_target
    (o : 'a Simplified.expr option)
  : Normalized.annotated_stmt list * Normalized.annotated_sexpr option =
  let normalized_opt =
    normalize_option (normalize_expr ctx in_loop exception_target) o in
  match normalized_opt with
  | None -> [], None
  | Some(bindings, result) -> bindings, Some(result)

and normalize_cmpop o =
  match o with
  | Simplified.Eq -> "__eq__"
  | Simplified.NotEq -> "__ne__"
  | Simplified.Lt -> "__lt__"
  | Simplified.LtE -> "__le__"
  | Simplified.Gt -> "__gt__"
  | Simplified.GtE -> "__ge__"
  | Simplified.In -> "__contains__"
  | Simplified.NotIn -> failwith "the NotIn operator is not supported" (* TODO *)

and normalize_sign s =
  match s with
  | Simplified.Pos -> Normalized.Pos
  | Simplified.Neg -> Normalized.Neg
  | Simplified.Zero -> Normalized.Zero

and normalize_number n =
  match n with
  | Simplified.Int sgn -> Normalized.Int(normalize_sign sgn)
  | Simplified.Float sgn -> Normalized.Float(normalize_sign sgn)

and normalize_str s =
  match s with
  | Simplified.StringAbstract -> Normalized.StringAbstract
  | Simplified.StringLiteral (s) -> Normalized.StringLiteral (s)

and normalize_builtin b =
  match b with
  | Simplified.Builtin_bool -> Normalized.Builtin_bool
  | Simplified.Builtin_slice -> Normalized.Builtin_slice
  | Simplified.Builtin_type -> Normalized.Builtin_type
