(* open Batteries;; *)
open Lamia_ast;;
open Lamia_conversion_builtin_names;;
open Lamia_conversion_utils;;
open Lamia_conversion_ctx;;

(* This file contains all definitions of python builtins, global helper
   functions like *getcall, etc *)

let annot = Python2_ast.Pos.of_pos Lexing.dummy_pos;;

let scope_def ctx =
  let empty_name = Value_variable(gen_unique_name ctx annot) in
  List.map (annotate_directive ctx annot) @@
  [
    Let_expression(empty_name, Empty_binding);
    Let_alloc(python_scope);
    Store(python_scope, empty_name);
  ]
;;

let get_from_scope_def ctx =
  let target = Value_variable(gen_unique_name ctx annot) in
  let lookup_in_parent =
    let parent_retval = Memory_variable(gen_unique_name ctx annot) in
    [
      Let_call_function(parent_retval, get_from_parent_scope, [target]);
      If_result_memory(parent_retval);
    ]
  in
  let local_lookup, local_result =
    get_from_binding ctx annot target python_scope lookup_in_parent
  in
  Function_expression(
    [target],
    Block(
      local_lookup @
      [
        annotate_directive ctx annot @@
        If_result_memory(local_result);
      ]
    )
  )
;;

let get_from_parent_scope_def ctx =
  let target_name = Value_variable(gen_unique_name ctx annot) in
  List.map (annotate_directive ctx annot) @@
  [
    Let_expression(get_from_parent_scope,
                   Function_expression(
                     [target_name],
                     Block
                       [
                         (* TODO: allocate and throw a NameError *)
                       ]));
  ]
;;

(* let int_add_def ctx =
  let func_name = Value_variable(gen_unique_name ctx annot) in
  let arglist = Value_variable(gen_unique_name ctx annot) in
  let func_val =
    Function_expression(
      [arglist],
      Block
    )
  in
  []

;; *)
(* TODO: Define function values *)
(* TODO: Store in global memlocs *)
