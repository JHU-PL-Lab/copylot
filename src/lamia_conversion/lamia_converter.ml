open Batteries;;
open Lamia_ast;;
open Python2_normalized_ast;;
open Lamia_conversion_ctx;;
open Lamia_conversion_utils;;
open Lamia_object_defs;;

let rec convert_module
    (ctx : conversion_context)
    (m : 'a modl)
  : block =
  let Module(stmts, _) = m in
  (* TODO: Preamble, scope setup, etc *)
  Block(map_and_concat (convert_stmt ctx) stmts)

and convert_stmt
    (ctx : conversion_context)
    (s : 'a stmt)
  : statement list =
  (* let convert_stmt = convert_stmt ctx in *)
  let annotate_directive annot d = annotate_directive ctx annot d in
  match s with
  | Assign (id, value, annot) ->
    let value_bindings, value_result = convert_expr ctx value in
    value_bindings @
    assign_python_variable ctx annot id value_result

  | Return (x, annot) ->
    let lookup_bindings, lookup_result = lookup ctx annot x in
    lookup_bindings @
    [
      annotate_directive annot @@
      Lamia_ast.Return(lookup_result);
    ]

  | While (test, body, annot) ->
    let value_bindings, value_result = lookup_starvalue ctx annot test in
    value_bindings @
    [
      annotate_directive annot @@
      Lamia_ast.While(value_result,
                      Block(map_and_concat (convert_stmt ctx) body @
                            value_bindings));
    ]

  | If (test, body, orelse, annot) ->
    let value_bindings, value_result = lookup_starvalue ctx annot test in
    let test_result = Value_variable(gen_unique_name ctx annot) in
    let test_bindings =
      value_bindings @
      [
        annotate_directive annot @@
        Let_get(test_result, value_result);
      ]
    in

    let dummy_variable = Value_variable(gen_unique_name ctx annot) in

    let dummy_return =
      let dummy_retval = Value_variable(gen_unique_name ctx annot) in
      List.map (annotate_directive annot)
        [
          Let_expression(dummy_retval, None_literal);
          If_result_value(dummy_retval);
        ]
    in

    let new_body =
      map_and_concat (convert_stmt ctx) body @ dummy_return
    in
    let new_orelse =
      map_and_concat (convert_stmt ctx) orelse @ dummy_return
    in

    test_bindings @
    [
      annotate_directive annot @@
      Let_conditional_value(dummy_variable,
                            test_result,
                            Block(new_body),
                            Block(new_orelse))
    ]

  | Raise (x, annot) ->
    let lookup_bindings, lookup_result = lookup ctx annot x in
    lookup_bindings @
    [
      annotate_directive annot @@
      Lamia_ast.Raise(lookup_result);
    ]

  | TryExcept (body, exn_name, handler, annot) ->
    let exn_memloc = Memory_variable(gen_unique_name ctx annot) in
    let new_body = map_and_concat (convert_stmt ctx) body in
    let new_handler =
      assign_python_variable ctx annot exn_name exn_memloc @
      map_and_concat (convert_stmt ctx) handler
    in
    [
      annotate_directive annot @@
      Try_except(Block(new_body),
                 exn_memloc,
                 Block(new_handler))
    ]

  | Pass _ ->
    []

  | Break _ ->
    raise @@ Jhupllib_utils.Not_yet_implemented "Convert break stmt"

  | Continue _ ->
    raise @@ Jhupllib_utils.Not_yet_implemented "Convert continue stmt"

and convert_expr
    (ctx : conversion_context)
    (s : 'a expr)
  : statement list * memory_variable =
  let annotate_directive annot d = annotate_directive ctx annot d in
  match s with
  | Binop (left, op, right, annot) ->
    let left_lookups, left_result = lookup ctx annot left in
    let right_lookups, right_result = lookup ctx annot right in
    let value_bindings, value_result =
      match op with
      | Is ->
        let result = Value_variable(gen_unique_name ctx annot) in
        left_lookups @ right_lookups @
        [
          annotate_directive annot @@
          Let_is(result, left_result, right_result);
        ],
        result
    in
    let obj_bindings, obj_result = wrap_bool ctx annot value_result in
    value_bindings @ obj_bindings, obj_result

  | _ ->
    raise @@ Jhupllib_utils.Not_yet_implemented "Convert_expr"
