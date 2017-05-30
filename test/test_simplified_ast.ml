open OUnit2
open Batteries
open Jhupllib
open Python2_parser
open Lexing
open Python2_simplified_ast
module Lift = Python2_analysis_conversion
module Simplify = Python2_ast_simplifier

let annot = Python2_ast.Pos.of_pos Lexing.dummy_pos;;

let string_of_stmt e  = Pp_utils.pp_to_string
    (Pp_utils.pp_list (pp_stmt (fun _ _ -> ()))) e;;
let equivalent_stmt e1 e2 = List.eq (equal_stmt ( fun _ _ -> true)) e1 e2;;

let string_of_modl m = Pp_utils.pp_to_string
    (pp_modl (fun _ _ -> ())) m;;
let equivalent_modl m1 m2 = equal_modl ( fun _ _ -> true) m1 m2;;

let parse_stmt_from_string_safe str =
  try
    parse_stmt_from_string str
  with
  | Python2_parser.Parse_error p ->
    assert_failure (Printf.sprintf "Error in line %d, col %d."
                      p.pos_lnum p.pos_cnum)
;;

let parse_from_string_safe str =
  try
    parse_from_string str
  with
  | Python2_parser.Parse_error p ->
    assert_failure (Printf.sprintf "Error in line %d, col %d."
                      p.pos_lnum p.pos_cnum)
;;

(* Functions to hide testing boilerplate *)

let gen_module_test (name : string) (prog : string) (expected : 'a stmt list) =
  name>::
  ( fun _ ->
      let concrete = parse_from_string_safe (prog ^ "\n") in
      let abstract = Lift.lift_modl concrete in
      let actual = Simplify.simplify_modl abstract in
      assert_equal ~printer:string_of_modl ~cmp:equivalent_modl
        (Module(expected, annot)) actual
  )

let gen_stmt_test (name : string) (prog : string) (expected : 'a expr) =
  name>::
  ( fun _ ->
      let concrete = parse_stmt_from_string_safe (prog ^ "\n") in
      let abstract = List.map Lift.lift_stmt concrete in
      let actual = List.concat (List.map Simplify.simplify_stmt abstract) in
      assert_equal ~printer:string_of_stmt ~cmp:equivalent_stmt
        [(Expr(expected, annot))] actual
  )

let int_test = gen_stmt_test "int_test"
    "4"
    (Num(Int(Pos), annot))
;;

let float_test = gen_stmt_test "float_test"
    "1.7"
    (Num(Float(Pos), annot))
;;

let float_zero_test = gen_stmt_test "float_zero_test"
    "0.0"
    (Num(Float(Zero), annot))
;;

let unop_test = gen_stmt_test "unop_test_1"
    "+4"
    (UnaryOp(UAdd, Num(Int(Pos), annot), annot))
;;

let unop_not_test = gen_stmt_test "unop_not_test"
    "not x"
    (UnaryOp(Not, Name("x", annot), annot))
;;

let boolop_and_test = gen_stmt_test "boolop_and_test"
    "x and True and -5"
    (BoolOp(
        And,
        [
          Name("x", annot);
          Bool(true, annot);
          Num(Int(Neg), annot);
        ],
        annot
      )
    )
;;

let boolop_or_test = gen_stmt_test "boolop_or_test"
    "x or False or 0"
    (BoolOp(
        Or,
        [
          Name("x", annot);
          Bool(false, annot);
          Num(Int(Zero), annot);
        ],
        annot
      )
    )
;;

let boolop_all_test = gen_stmt_test "boolop_all_test"
    "a and b and not c or d and not c or not a and not b"
    ( (* Expected order of operations is not, then and, then or *)
      BoolOp(
        Or,
        [
          BoolOp(And,
                 [
                   Name("a", annot);
                   Name("b", annot);
                   UnaryOp(Not, Name("c", annot), annot);
                 ],
                 annot);
          BoolOp(And,
                 [
                   Name("d", annot);
                   UnaryOp(Not, Name("c", annot), annot);
                 ],
                 annot);
          BoolOp(And,
                 [
                   UnaryOp(Not, Name("a", annot), annot);
                   UnaryOp(Not, Name("b", annot), annot);
                 ],
                 annot);
        ],
        annot
      )
    )
;;

let var_assign_test = gen_module_test "var_assign_test"
    "x = 5"
    [
      Assign(
        Name("unique_name_placeholder", annot),
        Num(Int(Pos), annot),
        annot
      );
      Assign(
        Name("x", annot),
        Name("unique_name_placeholder", annot),
        annot
      )
    ]
;;

let var_double_assign_test = gen_module_test "var_double_assign_test"
    "x = y = 5"
    [
      Assign(
        Name("unique_name_placeholder", annot),
        Num(Int(Pos), annot),
        annot
      );
      Assign(
        Name("x", annot),
        Name("unique_name_placeholder", annot),
        annot
      );
      Assign(
        Name("y", annot),
        Name("unique_name_placeholder", annot),
        annot
      )
    ]
;;

let var_assign_from_tuple_test = gen_module_test "var_assign_from_tuple_test"
    "i, j = (-1,0)" (* FIXME: This entire test *)
    [
      Assign(
        Tuple(
          [
            Name("i", annot);
            Name("j", annot);
          ],
          annot)
        ,
        Tuple(
          [
            Num(Int(Neg), annot);
            Num(Int(Zero), annot);
          ],
          annot),
        annot)
    ]
;;

let var_aug_assign_test = gen_module_test "var_aug_assign_test"
    "x *= -5"
    [
      Assign(
        Name("unique_name_placeholder", annot),
        BinOp(Name("x", annot),
              Mult,
              Num(Int(Neg), annot),
              annot
             ),
        annot
      );
      Assign(
        Name("x", annot),
        Name("unique_name_placeholder", annot),
        annot
      )
    ]
;;

let var_cmp_test = gen_module_test "var_cmp_test"
    "x <= 42"
    [
      Expr(
        Compare(
          Name("x", annot),
          [LtE],
          [Num(Int(Pos), annot)],
          annot
        ),
        annot
      )
    ]
;;

let funcdef_test = gen_module_test "funcdef_test"
    "def test_function(arg1,arg2):\n\treturn arg1"
    [
      FunctionDef("test_function",
                  [
                    Name("arg1",
                         annot);
                    Name("arg2",
                         annot)
                  ],
                  [ (* Body *)
                    Return(Some(Name("arg1", annot)),
                           annot)
                  ],
                  annot)
    ]
;;

let call_test = gen_stmt_test "call_test"
    "func(1,x,'foo')"
    (Call(
        Name("func", annot),
        [
          Num(Int(Pos), annot);
          Name("x", annot);
          Str(StringLiteral("foo"), annot);
        ],
        annot))
;;

let attribute_test = gen_stmt_test "attribute_test"
    "obj.member_var"
    (Attribute(
        Name("obj", annot),
        "member_var",
        annot))
;;

let attribute_call_test = gen_stmt_test "attribute_test"
    "obj.member_func()"
    (Call(
        Attribute(
          Name("obj", annot),
          "member_func",
          annot),
        [],
        annot
      ))
;;

let if_test = gen_module_test "if_test"
    "if x > 2:\n\tx = 3\nelif x < 0: x *= -1\nelse: pass"
    [
      If(
        Compare(Name("x", annot),
                [Gt],
                [Num(Int(Pos), annot)],
                annot),
        [
          Assign(
            Name("unique_name_placeholder", annot),
            Num(Int(Pos), annot),
            annot
          );
          Assign(
            Name("x", annot),
            Name("unique_name_placeholder", annot),
            annot
          )
        ],
        [
          If(
            Compare(Name("x", annot),
                    [Lt],
                    [Num(Int(Zero), annot)],
                    annot),
            [
              Assign(
                Name("unique_name_placeholder", annot),
                BinOp(Name("x", annot),
                      Mult,
                      Num(Int(Neg), annot),
                      annot
                     ),
                annot
              );
              Assign(
                Name("x", annot),
                Name("unique_name_placeholder", annot),
                annot
              )
            ],
            [Pass(annot)],
            annot
          )
        ],
        annot
      )
    ]
;;

let print_test = gen_module_test "print_test"
    "print 1,x,'foo'"
    [
      Print(None,
            [
              Num(Int(Pos), annot);
              Name("x", annot);
              Str(StringLiteral("foo"),annot);
            ],
            true,
            annot)
    ]
;;

let tuple_test = gen_stmt_test "tuple_test"
    "(1,2,3,4)"
    (Tuple (
        [
          Num(Int(Pos), annot);
          Num(Int(Pos), annot);
          Num(Int(Pos), annot);
          Num(Int(Pos), annot);
        ],
        annot
      ))
;;

let while_test = gen_module_test "while_test"
    "while x < 9001:\n\tx = x+1"
    [
      While(
        Compare(
          Name("x", annot),
          [Lt],
          [Num(Int(Pos), annot)],
          annot),
        [
          Assign(
            Name("unique_name_placeholder", annot),
            BinOp(Name("x", annot),
                  Add,
                  Num(Int(Pos), annot),
                  annot
                 ),
            annot
          );
          Assign(
            Name("x", annot),
            Name("unique_name_placeholder", annot),
            annot
          )
        ],
        annot
      )
    ]
;;

let for_test = gen_module_test "for_test"
    "for i in list:\n\ti+=1"
    [
      (* FIXME: This
         For(
         Name("i", annot),
         Name("list", annot),
         [
          AugAssign(
            Name("i", annot),
            Add,
            Num(Int(Pos), annot),
            annot)
         ],
         [],
         annot);
      *)
    ]
;;

let break_test = gen_module_test "break_test"
    "while x < 9001:\n\tbreak"
    [
      While(
        Compare(
          Name("x", annot),
          [Lt],
          [Num(Int(Pos), annot)],
          annot),
        [
          Break(annot)
        ],
        annot
      )
    ]
;;

let continue_test = gen_module_test "continue_test"
    "while x < 9001:\n\tcontinue"
    [
      While(
        Compare(
          Name("x", annot),
          [Lt],
          [Num(Int(Pos), annot)],
          annot),
        [
          Continue(annot)
        ],
        annot
      )
    ]
;;

let raise_test_no_args = gen_module_test "raise_test_no_args"
    "raise"
    [Raise(None, None, annot)]
;;

let raise_test_one_arg = gen_module_test "raise_test_no_args"
    "raise ValueError"
    [Raise(
        Some(Name("ValueError", annot)),
        None,
        annot)]
;;

let raise_test_two_args = gen_module_test "raise_test_no_args"
    "raise ValueError, 5"
    [Raise(
        Some(Name("ValueError", annot)),
        Some(Num(Int(Pos), annot)),
        annot)]
;;

let try_block =
  "try:" ^
  "\n\tx = 5" ^
  "\nexcept ValueError:" ^
  "\n\tprint 'Error'" ^
  "\nexcept StopIteration as e:" ^
  "\n\tprint 'Other Error'" ^
  "\n"
;;

let try_test = gen_module_test "try_test"
    try_block
    [
      TryExcept(
        [
          Assign(
            Name("unique_name_placeholder", annot),
            Num(Int(Pos), annot),
            annot);
          Assign(
            Name("x", annot),
            Name("unique_name_placeholder", annot),
            annot)
        ],
        [
          ExceptHandler(
            Some(Name("ValueError", annot)),
            None,
            [
              Print(None,
                    [Str (StringLiteral("Error"), annot)],
                    true,
                    annot)
            ],
            annot);
          ExceptHandler(
            Some(Name("StopIteration", annot)),
            Some(Name("e", annot)),
            [
              Print (None,
                     [Str(StringLiteral("Other Error"),annot)],
                     true,
                     annot)
            ],
            annot)
        ],
        annot)
    ]
;;

let triangle_def =
  "def triangle(n):" ^
  "\n\tcount = 0" ^
  "\n\ti=0" ^
  "\n\twhile count < n:" ^
  "\n\t\ti += count" ^
  "\n\t\tcount = count + 1" ^
  "\n\treturn i" ^
  "\n"
;;

let triangle_ast =
  FunctionDef(
    "triangle",
    [Name("n", annot)],
    [ (* Body *)
      Assign(
        Name("unique_name_placeholder", annot),
        Num(Int(Zero), annot),
        annot);
      Assign(
        Name("count", annot),
        Name("unique_name_placeholder", annot),
        annot
      );
      Assign(
        Name("unique_name_placeholder", annot),
        Num(Int(Zero), annot),
        annot);
      Assign(
        Name("i", annot),
        Name("unique_name_placeholder", annot),
        annot
      );
      While(
        Compare(
          Name("count", annot),
          [Lt],
          [Name("n", annot)],
          annot
        ),
        [
          Assign(
            Name("unique_name_placeholder", annot),
            BinOp(Name("i", annot),
                  Add,
                  Name("count", annot),
                  annot),
            annot);
          Assign(
            Name("i", annot),
            Name("unique_name_placeholder", annot),
            annot
          );
          Assign(
            Name("unique_name_placeholder", annot),
            BinOp(Name("count", annot), Add, Num(Int(Pos), annot), annot),
            annot);
          Assign(
            Name("count", annot),
            Name("unique_name_placeholder", annot),
            annot
          )
        ],
        annot
      );
      Return(Some(Name("i", annot)), annot);
    ],
    annot
  )
;;

let big_test = gen_module_test "big_test"
    (triangle_def ^ "\n[triangle(1),triangle(7)]")
    [
      triangle_ast;
      Expr(List(
          [
            Call(
              Name("triangle", annot),
              [
                Num(Int(Pos), annot)
              ],
              annot
            );
            Call(
              Name("triangle", annot),
              [
                Num(Int(Pos), annot)
              ],
              annot
            );
          ],
          annot
        ),
           annot)
    ]
;;

(* Tests of lists and slicing *)
let list_str = "[1,2,3,'four','five',2+4]";;
let list_expr =
  List(
    [
      Num(Int(Pos),annot);
      Num(Int(Pos),annot);
      Num(Int(Pos),annot);
      Str(StringLiteral("four"), annot);
      Str(StringLiteral("five"), annot);
      BinOp(Num(Int(Pos),annot), Add, Num(Int(Pos),annot), annot);
    ],
    annot
  )

let list_test = gen_stmt_test "list_test"
    list_str
    list_expr;;

let list_in_test = gen_stmt_test "lst_in_test"
    ("5 in " ^ list_str)
    (Compare(
        Num(Int(Pos), annot),
        [In],
        [list_expr],
        annot
      )
    )
;;

let gen_slice_test (name : string) (slice : string) (expected_slice: 'a expr) =
  gen_stmt_test
    name
    (list_str ^ slice)
    (Call(
        Attribute(list_expr,
                  "__getitem__",
                  annot),
        [ expected_slice ],
        annot))
;;

let list_tests =
  [
    list_test;
    list_in_test;
    (gen_slice_test "slice_test_1" "[0]"
       (Num(Int(Zero),annot)));
    (gen_slice_test "slice_test2" "[5-2]"
       (BinOp(Num(Int(Pos),annot), Sub, Num(Int(Pos), annot), annot)));
    (gen_slice_test "slice_test3" "[2:]"
       (Call(Name("slice", annot),
             [
               Num(Int(Pos), annot);
               Name("None", annot);
               Name("None", annot);
             ],
             annot)));
    (gen_slice_test "slice_test4" "[:4]"
       (Call(Name("slice", annot),
             [
               Name("None", annot);
               Num(Int(Pos), annot);
               Name("None", annot);
             ],
             annot)));
    (gen_slice_test "slice_test5" "[::3]"
       (Call(Name("slice", annot),
             [
               Name("None", annot);
               Name("None", annot);
               Num(Int(Pos), annot);
             ],
             annot)));
    (gen_slice_test "slice_test6" "[2:4]"
       (Call(Name("slice", annot),
             [
               Num(Int(Pos), annot);
               Num(Int(Pos), annot);
               Name("None", annot);
             ],
             annot)));
    (gen_slice_test "slice_test7" "[2:4:-1]"
       (Call(Name("slice", annot),
             [
               Num(Int(Pos), annot);
               Num(Int(Pos), annot);
               Num(Int(Neg), annot);
             ],
             annot)));
  ]

(* Tests of various binary operations *)
let gen_binop_test (name : string) (prog : string) (lhs : 'a expr) (rhs : 'a expr) op =
  gen_stmt_test name prog (BinOp(lhs, op, rhs, annot))
;;

let binop_tests =
  [
    (gen_binop_test "add_int_test" "42 + 9001"
       (Num(Int(Pos), annot)) (Num(Int(Pos), annot)) Add);
    (gen_binop_test "add_float_test" "42.0 + 9001.75"
       (Num(Float(Pos), annot)) (Num(Float(Pos), annot)) Add);
    (gen_binop_test "add_int_float_test" "42 + -9001.5"
       (Num(Int(Pos), annot)) (Num(Float(Neg), annot)) Add);

    (gen_binop_test "add_str_test" "'foo' + 'bar'"
       (Str(StringLiteral("foo"), annot)) (Str(StringLiteral("bar"), annot)) Add);
    (gen_binop_test "add_int_str_test" "42 + 'foo'"
       (Num(Int(Pos), annot)) (Str(StringLiteral("foo"), annot)) Add);

    (gen_binop_test "sub_int_test" "42 - 9001"
       (Num(Int(Pos), annot)) (Num(Int(Pos), annot)) Sub);
    (gen_binop_test "mult_int_test" "42 * 9001"
       (Num(Int(Pos), annot)) (Num(Int(Pos), annot)) Mult);
    (gen_binop_test "div_int_test" "42 / 9001"
       (Num(Int(Pos), annot)) (Num(Int(Pos), annot)) Div);
    (gen_binop_test "mod_int_test" "42 % 9001"
       (Num(Int(Pos), annot)) (Num(Int(Pos), annot)) Mod);
    (gen_binop_test "pow_int_test" "42 ** 9001"
       (Num(Int(Pos), annot)) (Num(Int(Pos), annot)) Pow);

    (gen_binop_test "triple_binop_test" "(42 - 9001) + 17"
       (BinOp(Num(Int(Pos), annot),
              Sub,
              Num(Int(Pos), annot),
              annot))
       (Num(Int(Pos), annot))
       Add);

    (gen_binop_test "order_of_operations_test" "1+2*3"
       (Num(Int(Pos), annot))
       (BinOp(Num(Int(Pos), annot),
              Mult,
              Num(Int(Pos), annot),
              annot))
       Add);
  ]
(* Run the tests *)

let tests =
  "abstract_ast">:::
  [
    int_test;
    float_test;
    float_zero_test;
    unop_test;
    unop_not_test;
    boolop_and_test;
    boolop_or_test;
    boolop_all_test;
    var_assign_test;
    var_double_assign_test;
    (* var_assign_from_tuple_test; *)
    var_aug_assign_test;
    var_cmp_test;
    if_test;
    funcdef_test;
    call_test;
    attribute_test;
    attribute_call_test;
    tuple_test;
    print_test;
    while_test;
    (* for_test; *)
    break_test;
    continue_test;
    raise_test_no_args;
    raise_test_one_arg;
    raise_test_two_args;
    try_test;
    big_test;
  ]
  @ binop_tests
  @ list_tests