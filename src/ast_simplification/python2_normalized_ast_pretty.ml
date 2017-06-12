open Format
open Python2_normalized_ast

(* Default pretty printing *)

let rec pp_lines printer fmt = function
  | [] -> ()
  | [x] -> printer fmt x
  | x :: rest ->
    fprintf fmt "%a@\n%a" printer x (pp_lines printer) rest

and pp_option pp fmt = function
  | None -> ()
  | Some x -> pp fmt x

and pp_list pp fmt lst =
  let rec loop pp fmt = function
    | [] -> ()
    | [x] -> pp fmt x
    | x :: rest ->
        fprintf fmt "%a, %a" pp x (loop pp) rest
  in loop pp fmt lst
;;

let rec pp_modl fmt = function
  | Module (body, _) ->
    pp_lines pp_stmt fmt body

(* The statements should have line number. *)
and pp_stmt fmt {uid=uid;exception_target=exc;multi=_;body} =
  match body with
  | Assign (target,value) ->
    fprintf fmt "%a:%a = %a"
      pp_label (uid,exc)
      pp_id target
      pp_compound_expr value
  | FunctionDef (name,args,body) ->
    (* Python flavor FunctionDef: *)
    (* fprintf fmt "@[<4>%a:%a(%a):@\n%a@]" *)
    fprintf fmt "@[<4>%a:%a(%a) {@\n%a@]@\n}"
    pp_label (uid,exc)
      pp_id name
      (pp_list pp_id) args
      (pp_lines pp_stmt) body
  | Return (value) ->
    fprintf fmt "%a:return %a"
      pp_label (uid,exc)
      (pp_option pp_simple_expr) value
  | Print (_,values,_) ->
    fprintf fmt "%a:print %a" (* TODO: print dest if relevant *)
      pp_label (uid,exc)
      (pp_list pp_simple_expr) values
      (* (pp_option pp_simple_expr) dest *)
  | Raise (value) ->
    fprintf fmt "%a:raise %a"
      pp_label (uid,exc)
      pp_simple_expr value
  | Catch (name) ->
    fprintf fmt "%a:catch %a"
      pp_label (uid,exc)
      pp_id name
  | Pass ->
    fprintf fmt "%a:pass"
      pp_label (uid,exc)
  | Goto (dest) ->
    fprintf fmt "%a:goto %a"
      pp_label (uid,exc)
      pp_print_int dest
  | GotoIfNot (test,dest) ->
    fprintf fmt "%a:goto %a if not %a"
      pp_label (uid,exc)
      pp_print_int dest
      pp_simple_expr test
  | SimpleExprStmt (value) ->
    fprintf fmt "%a:%a"
      pp_label (uid,exc)
      pp_simple_expr value

and pp_compound_expr fmt {uid=_;exception_target=_;multi=_;body} =
  match body with
  | Call (func,args) ->
    fprintf fmt "%a(%a)"
      pp_simple_expr func
      (pp_list pp_simple_expr) args
  | Attribute (obj,attr) ->
    fprintf fmt "%a.%a"
      pp_simple_expr obj
      pp_id attr
  | List (lst) ->
    fprintf fmt "[%a]"
      (pp_list pp_simple_expr) lst
  | Tuple (lst) ->
    fprintf fmt "(%a)"
      (pp_list pp_simple_expr) lst
  | SimpleExpr (se) -> pp_simple_expr fmt se

and pp_simple_expr fmt {uid=_;exception_target=_;multi=_;body} =
  match body with
  | Literal (l) -> pp_literal fmt l
  | Name (id) -> pp_id fmt id

and pp_id fmt id =
  fprintf fmt "%s" id

and pp_literal fmt = function
  | Num (n) -> pp_num fmt n
  | Str (s) -> pp_str fmt s
  | Bool (b) -> pp_print_bool fmt b
  | Builtin (bi) -> pp_builtin fmt bi

and pp_num fmt = function
  | Int sgn -> fprintf fmt "Int%a" pp_sign sgn
  | Float sgn -> fprintf fmt "Float%a" pp_sign sgn

and pp_str fmt = function
  | StringAbstract -> fprintf fmt "StringAbstract"
  | StringLiteral s -> fprintf fmt "\"%s\"" (String.escaped s)

and pp_sign fmt= function
  | Pos -> fprintf fmt "+"
  | Neg -> fprintf fmt "-"
  | Zero -> fprintf fmt "0"

and pp_builtin fmt = function
  | Builtin_slice -> fprintf fmt "slice"
  | Builtin_bool -> fprintf fmt "bool"
  | Builtin_type -> fprintf fmt "type"


and pp_label fmt (uid,exc) =
  fprintf fmt "%a:%a"
    pp_print_int uid
    (pp_option pp_print_int) exc
;;
