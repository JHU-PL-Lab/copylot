open Python2_ast_types;;

type annotated_modl = modl annotation
[@@deriving eq, ord, show, to_yojson]

and annotated_stmt = stmt annotation
[@@deriving eq, ord, show, to_yojson]

and annotated_expr = expr annotation
[@@deriving eq, ord, show, to_yojson]

and modl =
  | Module of annotated_stmt list (* body *)
[@@deriving eq, ord, show]

and stmt =
    | Assign of identifier (* target *) * annotated_expr (* value *)
  | Return of identifier (* value *)
(* We maintain an invariant that the test statement of a while loop is always
   an actual boolean value. We also require that the test be an identifer, so
   that there is no more work to be done during normalization. This lets us
   ensure that we can append all necessary computation of the test value to the
   body of the while during simplification. *)
  | While of identifier (* test *) * annotated_stmt list (* body *) * annotated_stmt list (* orelse *)
  (* We maintain the same invariant for if statements as for while loops *)
  | If of identifier (* test *) * annotated_stmt list (* body *) * annotated_stmt list (* orelse *)
  (* Raise is very complicated, with different behaviors based on the
       number of arguments it recieves. For simplicity we require that
       it take exactly one argument, which is the value to be raised. *)
  | Raise of identifier (* value *)
  | TryExcept of annotated_stmt list (* body *) * identifier (* exn name *) * annotated_stmt list (* handlers *) * annotated_stmt list (* orelse *)
  | Pass
  | Break
  | Continue
[@@deriving eq, ord, show]

and expr =
    | UnaryOp of unaryop (* op *) * identifier (* value *)
  | Binop of identifier (* right *) * binop (* op *) * identifier (* right *)
  | Call of identifier (* func *) * identifier list (* args *)
  | Attribute of identifier (* object *) * string (* attr *)
  | List of identifier list (* elts *)
  | Tuple of identifier list (* elts *)
  | Num of number (* n *)
  | Str of string
  | Bool of bool
  | Name of identifier (* id *)
  | Builtin of builtin
  | FunctionVal of identifier list (* args *) * annotated_stmt list (* body *)
[@@deriving eq, ord, show]

and binop = Is
[@@deriving eq, ord, show]

and unaryop = Not
[@@deriving eq, ord, show]
