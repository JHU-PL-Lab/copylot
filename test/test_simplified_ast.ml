open OUnit2
open Batteries
open Jhupllib
open Python2_parser
open Lexing
module Abstract = Python2_abstract_ast
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
      Simplify.reset_unique_name ();
      assert_equal ~printer:string_of_modl ~cmp:equivalent_modl
        (Module(expected, annot)) actual
  )
;;

let gen_stmt_test (name : string) (prog : string) (expected : 'a expr) =
  name>::
  ( fun _ ->
      let concrete = parse_stmt_from_string_safe (prog ^ "\n") in
      let abstract = List.map Lift.lift_stmt concrete in
      let actual = List.concat (List.map Simplify.simplify_stmt abstract) in
      Simplify.reset_unique_name ();
      assert_equal ~printer:string_of_stmt ~cmp:equivalent_stmt
        [(Expr(expected, annot))] actual
  )
;;

let expect_error_test
    (name : string)
    (prog : 'a Abstract.stmt list)
    (expected : exn) =
  name>::
  (fun _ ->
     assert_raises
       expected
       (fun _ ->
          (List.concat (List.map Simplify.simplify_stmt prog)))
  )
;;

(* This is useful when creating tests for expect_error_test *)
let dummy_expr = Abstract.Num(Abstract.Int(Abstract.Zero), annot);;

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
        "$unique_name_0",
        Num(Int(Pos), annot),
        annot
      );
      Assign(
        "x",
        Name("$unique_name_0", annot),
        annot
      )
    ]
;;

let var_double_assign_test = gen_module_test "var_double_assign_test"
    "x = y = 5"
    [
      Assign(
        "$unique_name_0",
        Num(Int(Pos), annot),
        annot
      );
      Assign(
        "x",
        Name("$unique_name_0", annot),
        annot
      );
      Assign(
        "y",
        Name("$unique_name_0", annot),
        annot
      )
    ]
;;

let assign_iterator obj num =
  Assign(
    "$unique_name_" ^ string_of_int num,
    Attribute(
      Call(
        Attribute(
          obj,
          "__iter__",
          annot
        ),
        [],
        annot
      ),
      "next",
      annot),
    annot
  )
;;

let var_assign_from_tuple_test = gen_module_test "var_assign_from_tuple_test"
    "i, j = (-1,0)"
    [
      Assign(
        "$unique_name_0",
        Tuple(
          [
            Num(Int(Neg), annot);
            Num(Int(Zero), annot);
          ],
          annot),
        annot);

      assign_iterator (Name("$unique_name_0", annot)) 1;

      TryExcept(
        [
          Assign(
            "$unique_name_2",
            Call(Name("$unique_name_1", annot), [], annot),
            annot);
          Assign(
            "$unique_name_3",
            Call(Name("$unique_name_1", annot), [], annot),
            annot);
          TryExcept(
            [
              Expr(
                Call(Name("$unique_name_1", annot), [], annot),
                annot
              );
              Raise(
                Some(Name("ValueError", annot)),
                Some(Str(StringLiteral("too many values to unpack"),
                         annot)),
                annot);
            ],
            [ExceptHandler(
                Some(Name("StopIteration", annot)),
                None,
                [
                  Pass(annot)
                ],
                annot
              )
            ],
            annot
          )
        ],
        [ExceptHandler(
            Some(Name("StopIteration", annot)),
            None,
            [
              Raise(
                Some(Name("ValueError", annot)),
                Some(Str(StringAbstract, annot)),
                annot)
            ],
            annot
          )],
        annot);
      Assign(
        "$unique_name_4",
        Name("$unique_name_2", annot),
        annot);
      Assign(
        "i",
        Name("$unique_name_4", annot),
        annot);
      Assign(
        "$unique_name_5",
        Name("$unique_name_3", annot),
        annot);
      Assign(
        "j",
        Name("$unique_name_5", annot),
        annot);
    ]
;;

let assign_to_index_test = gen_module_test "assign_to_index_test"
    "list[1+2] = 3"
    [
      Assign(
        "$unique_name_0",
        Num(Int(Pos), annot),
        annot);
      Expr(
        Call(
          Attribute(
            Name("list", annot),
            "__setitem__",
            annot),
          [
            BinOp(Num(Int(Pos), annot), Add, Num(Int(Pos), annot), annot);
            Name("$unique_name_0", annot);
          ],
          annot
        ),
        annot
      )
    ]
;;

let assign_to_slice_test = gen_module_test "assign_to_slice_test"
    "list[1:2] = 3"
    [
      Assign(
        "$unique_name_0",
        Num(Int(Pos), annot),
        annot);
      Expr(
        Call(
          Attribute(
            Name("list", annot),
            "__setitem__",
            annot),
          [
            Call(
              Name("slice", annot),
              [
                Num(Int(Pos), annot);
                Num(Int(Pos), annot);
                Name("None", annot);
              ],
              annot
            );
            Name("$unique_name_0", annot);
          ],
          annot
        ),
        annot
      )
    ]
;;

let assign_to_attribute_test = gen_module_test "assign_to_attribute_test"
    "obj.member = 7"
    [
      Assign(
        "$unique_name_0",
        Num(Int(Pos), annot),
        annot);
      Expr(
        Call(
          Attribute(
            Name("obj", annot),
            "__setattr__",
            annot
          ),
          [
            Str(StringLiteral("member"), annot);
            Name("$unique_name_0", annot);
          ],
          annot
        ),
        annot
      )
    ]
;;

let var_aug_assign_test = gen_module_test "var_aug_assign_test"
    "x *= -5"
    [
      Assign(
        "$unique_name_0",
        BinOp(Name("x", annot),
              Mult,
              Num(Int(Neg), annot),
              annot
             ),
        annot
      );
      Assign(
        "x",
        Name("$unique_name_0", annot),
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

let gen_some_abstract_assignment target =
  Abstract.Assign(
    [target],
    dummy_expr,
    annot)
;;

let bad_assign_tests =
  [
    expect_error_test "assign_to_num"
      [(gen_some_abstract_assignment
          (Abstract.Num(Abstract.Int(Abstract.Zero), annot)))]
      (Failure("can't assign to literal"));
    expect_error_test "assign_to_str"
      [(gen_some_abstract_assignment
          (Abstract.Str(Abstract.StringAbstract, annot)))]
      (Failure("can't assign to literal"));
    expect_error_test "assign_to_bool"
      [(gen_some_abstract_assignment
          (Abstract.Bool(true, annot)))]
      (Failure("can't assign to literal"));
    expect_error_test "assign_to_boolop"
      [(gen_some_abstract_assignment
          (Abstract.BoolOp(Abstract.And, [dummy_expr; dummy_expr], annot)))]
      (Failure("can't assign to operator"));
    expect_error_test "assign_to_binop"
      [(gen_some_abstract_assignment
          (Abstract.BinOp(dummy_expr, Abstract.Add, dummy_expr, annot)))]
      (Failure("can't assign to operator"));
    expect_error_test "assign_to_unaryop"
      [(gen_some_abstract_assignment
          (Abstract.UnaryOp(Abstract.UAdd, dummy_expr, annot)))]
      (Failure("can't assign to operator"));
    expect_error_test "assign_to_ifexp"
      [(gen_some_abstract_assignment
          (Abstract.IfExp(dummy_expr, dummy_expr, dummy_expr, annot)))]
      (Failure("can't assign to conditional expression"));
    expect_error_test "assign_to_compare"
      [(gen_some_abstract_assignment
          (Abstract.Compare(dummy_expr, [Abstract.Lt], [dummy_expr], annot)))]
      (Failure("can't assign to comparison"));
    expect_error_test "assign_to_call"
      [(gen_some_abstract_assignment
          (Abstract.Call(dummy_expr, [], [], None, None, annot)))]
      (Failure("can't assign to function call"));
  ]
;;

let funcdef_test = gen_module_test "funcdef_test"
    "def test_function(arg1,arg2):\n\treturn arg1"
    [
      FunctionDef("test_function",
                  [
                    "arg1";
                    "arg2";
                  ],
                  [ (* Body *)
                    Return(Some(Name("arg1", annot)),
                           annot)
                  ],
                  annot)
    ]
;;

let bad_funcdef_test = expect_error_test "bad_funcdef_test"
    [
      Abstract.FunctionDef(
        "func",
        ([Abstract.Num(Abstract.Int(Abstract.Pos), annot)],
         None,
         None,
         []),
        [Abstract.Pass(annot)],
        [],
        annot
      )
    ]
    (Failure("The arguments in a function definition must be identifiers"))
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
            "$unique_name_1",
            Num(Int(Pos), annot),
            annot
          );
          Assign(
            "x",
            Name("$unique_name_1", annot),
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
                "$unique_name_0",
                BinOp(Name("x", annot),
                      Mult,
                      Num(Int(Neg), annot),
                      annot
                     ),
                annot
              );
              Assign(
                "x",
                Name("$unique_name_0", annot),
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
            "$unique_name_0",
            BinOp(Name("x", annot),
                  Add,
                  Num(Int(Pos), annot),
                  annot
                 ),
            annot
          );
          Assign(
            "x",
            Name("$unique_name_0", annot),
            annot
          )
        ],
        annot
      )
    ]
;;

let for_test = gen_module_test "for_test"
    "for i in list:\n\tf(i)"
    [
      assign_iterator (Name("list", annot)) 1;
      Assign(
        "$unique_name_0",
        Name("$unique_name_1", annot),
        annot
      );
      TryExcept(
        [
          While(
            Bool(true, annot),
            [
              Assign(
                "$unique_name_2",
                Call(Name("$unique_name_0", annot), [], annot),
                annot
              );
              Assign(
                "i",
                Name("$unique_name_2", annot),
                annot
              );
              Expr(Call(Name("f", annot), [Name("i", annot)], annot), annot);
            ],
            annot
          )
        ],
        [
          ExceptHandler(
            Some(Name("StopIteration", annot)),
            None,
            [Pass(annot)],
            annot
          )
        ],
        annot
      )
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
            "$unique_name_0",
            Num(Int(Pos), annot),
            annot);
          Assign(
            "x",
            Name("$unique_name_0", annot),
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
            Some("e"),
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

let bad_exception_handler_test = expect_error_test
    "bad_exception_handler_test"
    [Abstract.TryExcept(
        [],
        [
          Abstract.ExceptHandler(
            Some(Abstract.Name("foo", Abstract.Load, annot)),
            Some(dummy_expr),
            [],
            annot
          )
        ],
        [],
        annot
      )]
    (Failure("Second argument to exception handler must be an identifier"))
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
    ["n"],
    [ (* Body *)
      Assign(
        "$unique_name_0",
        Num(Int(Zero), annot),
        annot);
      Assign(
        "count",
        Name("$unique_name_0", annot),
        annot
      );
      Assign(
        "$unique_name_1",
        Num(Int(Zero), annot),
        annot);
      Assign(
        "i",
        Name("$unique_name_1", annot),
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
            "$unique_name_2",
            BinOp(Name("i", annot),
                  Add,
                  Name("count", annot),
                  annot),
            annot);
          Assign(
            "i",
            Name("$unique_name_2", annot),
            annot
          );
          Assign(
            "$unique_name_3",
            BinOp(Name("count", annot), Add, Num(Int(Pos), annot), annot),
            annot);
          Assign(
            "count",
            Name("$unique_name_3", annot),
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
    var_assign_from_tuple_test;
    assign_to_index_test;
    assign_to_slice_test;
    assign_to_attribute_test;
    var_aug_assign_test;
    var_cmp_test;
    if_test;
    funcdef_test;
    bad_funcdef_test;
    call_test;
    attribute_test;
    attribute_call_test;
    tuple_test;
    print_test;
    while_test;
    for_test;
    break_test;
    continue_test;
    raise_test_no_args;
    raise_test_one_arg;
    raise_test_two_args;
    try_test;
    bad_exception_handler_test;
    big_test;
  ]
  @ binop_tests
  @ list_tests
  @ bad_assign_tests
