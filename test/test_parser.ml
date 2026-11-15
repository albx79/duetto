module A = Duetto.Ast.Unit
open A

type test_expr = expr
type test_expr_node = expr_node
type test_type_expr = type_expr
type test_type_expr_node = type_expr_node
type test_struct_entry = struct_entry
type test_struct_entry_node = struct_entry_node

let parse src =
  let lexbuf = Lexing.from_string src in
  Duetto.Parse.parse_expr_unit lexbuf

let failures = ref 0

let check name src expected =
  match parse src with
  | actual when actual = expected -> ()
  | actual ->
      incr failures;
      Printf.printf "FAIL %s\n  expected: %s\n  actual:   %s\n" name
        (show_expr expected)
        (show_expr actual)
  | exception Duetto.Diagnostic.Error e ->
      incr failures;
      Printf.printf "FAIL %s\n  expected parse success\n  actual error: %s\n" name
        (Duetto.Diagnostic.string_of_error e)

let check_error name src =
  match parse src with
  | _ ->
      incr failures;
      Printf.printf "FAIL %s\n  expected parse error\n  actual: parse succeeded\n" name
  | exception Duetto.Diagnostic.Error _ ->
      ()

let check_file name src expected =
  match Duetto.Parse.parse_unit (Lexing.from_string src) with
  | actual when actual = expected -> ()
  | actual ->
      incr failures;
      Printf.printf "FAIL %s\n  expected: %s\n  actual:   %s\n" name
        (show_expr expected)
        (show_expr actual)
  | exception Duetto.Diagnostic.Error e ->
      incr failures;
      Printf.printf "FAIL %s\n  expected parse success\n  actual error: %s\n" name
        (Duetto.Diagnostic.string_of_error e)

let check_file_error name src expected =
  match Duetto.Parse.parse_unit (Lexing.from_string src) with
  | _ ->
      incr failures;
      Printf.printf "FAIL %s\n  expected parse error\n  actual: parse succeeded\n" name
  | exception Duetto.Diagnostic.Error e ->
      let actual = Duetto.Diagnostic.string_of_error e in
      if expected <> "" && actual <> expected then begin
        incr failures;
        Printf.printf "FAIL %s\n  expected error: %s\n  actual error:   %s\n"
          name expected actual
      end

(* Files under test/duetto that must parse. *)
let check_accepted_file path =
  let ic = open_in_bin path in
  let src = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let lexbuf = Lexing.from_string src in
  Lexing.set_filename lexbuf path;
  match Duetto.Parse.parse_unit lexbuf with
  | _ -> ()
  | exception Duetto.Diagnostic.Error e ->
      incr failures;
      Printf.printf "FAIL %s\n  expected parse success\n  actual error: %s\n" path
        (Duetto.Diagnostic.string_of_error e)

let () =
  check_accepted_file "duetto/accepted-specs.duetto";
  check "label" "'eq" (Label "eq");
  check "label comparison" "f(x) == 'lt" (Eq (Call (Ident "f", [Ident "x"]), Label "lt"));
  check "case on labels" "case r { 'lt -> \"less\", 'eq -> \"equal\", 'gt -> \"greater\" }"
    (Case (Ident "r", [
      { pattern = Label_pattern "lt"; body = String "less" };
      { pattern = Label_pattern "eq"; body = String "equal" };
      { pattern = Label_pattern "gt"; body = String "greater" };
    ]));
  check "case trailing comma" "case x { 'a -> 1, }"
    (Case (Ident "x", [{ pattern = Label_pattern "a"; body = Num "1" }]));
  check "case on a comparison" "case a == b { 'true -> 'eq, 'false -> 'lt }"
    (Case (Eq (Ident "a", Ident "b"), [
      { pattern = Label_pattern "true"; body = Label "eq" };
      { pattern = Label_pattern "false"; body = Label "lt" };
    ]));
  check "case on records" "case e { { num } -> num, { add } -> eval(add.l) + eval(add.r) }"
    (Case (Ident "e", [
      { pattern = Record_pattern ["num"]; body = Ident "num" };
      { pattern = Record_pattern ["add"];
        body = Add (Call (Ident "eval", [Proj (Ident "add", "l")]),
                    Call (Ident "eval", [Proj (Ident "add", "r")])) };
    ]));
  check "record patterns" "case r { {} -> 0, { a, b } -> 1, { a, } -> 2, { a, b, .. } -> 3, { .. } -> 4 }"
    (Case (Ident "r", [
      { pattern = Record_pattern []; body = Num "0" };
      { pattern = Record_pattern ["a"; "b"]; body = Num "1" };
      { pattern = Record_pattern ["a"]; body = Num "2" };
      { pattern = Open_record_pattern ["a"; "b"]; body = Num "3" };
      { pattern = Open_record_pattern []; body = Num "4" };
    ]));
  check "case branch with a block" "case x { 'a -> { y = 1, <<y } }"
    (Case (Ident "x", [
      { pattern = Label_pattern "a"; body = Struct [Local ("y", Num "1"); Result (Ident "y")] };
    ]));
  check "case branch with a lambda" "case x { 'a -> y -> y }"
    (Case (Ident "x", [
      { pattern = Label_pattern "a"; body = Lambda (["y"], Ident "y") };
    ]));
  check "nested case" "case x { 'a -> case y { 'b -> 1 }, 'c -> 2 }"
    (Case (Ident "x", [
      { pattern = Label_pattern "a";
        body = Case (Ident "y", [{ pattern = Label_pattern "b"; body = Num "1" }]) };
      { pattern = Label_pattern "c"; body = Num "2" };
    ]));
  check "case is an expression" "case x { 'a -> 1 } + 1"
    (Add (Case (Ident "x", [{ pattern = Label_pattern "a"; body = Num "1" }]), Num "1"));
  check_error "case needs a branch" "case x {}";
  check_error "case needs braces" "case x 'a -> 1";
  check_error "pattern is not an expression" "case x { y -> 1 }";
  check_error "open pattern ends with .." "case x { { .., a } -> 1 }";
  check_error "no comma after .." "case x { { a, .., } -> 1 }";
  check_error "no field values in patterns" "case x { { a: 1 } -> 1 }";
  check_error "branches need commas" "case x { 'a -> 1 'b -> 2 }";

  check_file "spec" "spec it works { ensure f(1) == 2 }"
    (Struct [Spec ("it works", [Ensure (Eq (Call (Ident "f", [Num "1"]), Num "2"))])]);
  check_file "spec with locals" "spec adds { x = f(1), y = x + 1, ensure y == 3, }"
    (Struct [
      Spec ("adds", [
        Local ("x", Call (Ident "f", [Num "1"]));
        Local ("y", Add (Ident "x", Num "1"));
        Ensure (Eq (Ident "y", Num "3"));
      ]);
    ]);
  check_file "empty spec" "spec nothing yet {}" (Struct [Spec ("nothing yet", [])]);
  check_file "specs among fields" "f: x -> x,\nspec identity { ensure f(1) == 1 },\ng: 2,"
    (Struct [
      Field ("f", Lambda (["x"], Ident "x"));
      Spec ("identity", [Ensure (Eq (Call (Ident "f", [Num "1"]), Num "1"))]);
      Field ("g", Num "2");
    ]);
  check_file "spec with nested struct" "spec s { r = { a: 1 }, ensure r.a == 1 }"
    (Struct [
      Spec ("s", [
        Local ("r", Struct [Field ("a", Num "1")]);
        Ensure (Eq (Proj (Ident "r", "a"), Num "1"));
      ]);
    ]);
  check_file_error "spec in a nested struct" "m: {\n  spec inner { ensure 1 == 1 }\n}"
    "The spec 'inner' at :2:3 is inside a nested struct; specs are allowed only at file level";
  check_file_error "spec in a lambda body" "f: x -> { spec inner {}, <<x }"
    "The spec 'inner' at :1:11 is inside a nested struct; specs are allowed only at file level";
  check_file_error "spec has no fields" "spec s { a: 1 }" "";
  check_file_error "spec has no result" "spec s { <<1 }" "";
  check_file_error "spec needs commas" "spec s { ensure a ensure b }" "";
  check_error "spec is not an expression" "spec s {}";

  check "num literal" "42" (Num "42");
  check "string literal" {|"hello"|} (String "hello");
  check "identifier" "x" (Ident "x");
  check "lambda one arg" "x -> x"
    (Lambda (["x"], Ident "x"));
  check "parenthesised ident" "(x)" (Ident "x");
  check "lambda one parenthesised arg" "(x) -> x"
    (Lambda (["x"], Ident "x"));
  check "lambda one arg trailing comma" "(x,) -> x"
    (Lambda (["x"], Ident "x"));
  check "lambda no args" "() -> 1"
    (Lambda ([], Num "1"));
  check "parenthesised sum" "(x + 1)"
    (Add (Ident "x", Num "1"));
  check "parenthesised projection" "(x.y)"
    (Proj (Ident "x", "y"));
  check_error "doubly parenthesised param" "((x)) -> x";
  check_error "expression as param" "(x.y) -> x";
  check_error "no tuples" "(x, y)";
  check "lambda many args" "(x, y) -> x"
    (Lambda (["x"; "y"], Ident "x"));
  check "lambda trailing comma" "(x, y,) -> y"
    (Lambda (["x"; "y"], Ident "y"));
  check "lambda body struct" "x -> { y = x, <<y }"
    (Lambda (["x"], Struct [
      Local ("y", Ident "x");
      Result (Ident "y");
    ]));
  check "projection" "person.name"
    (Proj (Ident "person", "name"));
  check "chained projection" "a.b.c"
    (Proj (Proj (Ident "a", "b"), "c"));
  check "arithmetic" "1 + 2"
    (Add (Num "1", Num "2"));
  check "concat identifiers" "a ++ b"
    (Concat (Ident "a", Ident "b"));
  check "concat projections" "person.name ++ suffix"
    (Concat (Proj (Ident "person", "name"), Ident "suffix"));
  check "call no args" "f()"
    (Call (Ident "f", []));
  check "call one arg" "f(x)"
    (Call (Ident "f", [Ident "x"]));
  check "call many args" "f(1, x, \"s\")"
    (Call (Ident "f", [Num "1"; Ident "x"; String "s"]));
  check "call trailing comma" "f(x, y,)"
    (Call (Ident "f", [Ident "x"; Ident "y"]));
  check "nested call" "h(f(x))"
    (Call (Ident "h", [Call (Ident "f", [Ident "x"])]));
  check "curried call" "f(x)(y)"
    (Call (Call (Ident "f", [Ident "x"]), [Ident "y"]));
  check "method call" "ord.compare(a, b)"
    (Call (Proj (Ident "ord", "compare"), [Ident "a"; Ident "b"]));
  check "projection of call result" "f(x).name"
    (Proj (Call (Ident "f", [Ident "x"]), "name"));
  check "call of parenthesised ident" "(f)(x)"
    (Call (Ident "f", [Ident "x"]));
  check "call of parenthesised lambda" "(x -> x)(1)"
    (Call (Lambda (["x"], Ident "x"), [Num "1"]));
  check "call binds tighter than arithmetic" "a + f(x) * 2"
    (Add (Ident "a", Mul (Call (Ident "f", [Ident "x"]), Num "2")));
  check "call in lambda body" "x -> h(f(x))"
    (Lambda (["x"], Call (Ident "h", [Call (Ident "f", [Ident "x"])])));
  check "lambda as argument" "map(xs, x -> x + 1)"
    (Call (Ident "map", [
      Ident "xs";
      Lambda (["x"], Add (Ident "x", Num "1"));
    ]));
  check "call with struct argument" "f({ a: 1 })"
    (Call (Ident "f", [Struct [Field ("a", Num "1")]]));
  check "call in struct" "{ tmp = f(x), <<tmp + 1 }"
    (Struct [
      Local ("tmp", Call (Ident "f", [Ident "x"]));
      Result (Add (Ident "tmp", Num "1"));
    ]);
  check_error "call lone comma" "f(,)";
  check_error "call missing close paren" "f(x";
  check "equality" "x == 1"
    (Eq (Ident "x", Num "1"));
  check "equality binds looser than arithmetic" "a + 1 == b * 2"
    (Eq (Add (Ident "a", Num "1"), Mul (Ident "b", Num "2")));
  check "equality binds looser than concat" "a ++ b == c"
    (Eq (Concat (Ident "a", Ident "b"), Ident "c"));
  check "equality of calls and projections" "f(x).name == p.name"
    (Eq (Proj (Call (Ident "f", [Ident "x"]), "name"), Proj (Ident "p", "name")));
  check "equality in lambda body" "x -> x == 1"
    (Lambda (["x"], Eq (Ident "x", Num "1")));
  check "parenthesised equality" "(a == b) == c"
    (Eq (Eq (Ident "a", Ident "b"), Ident "c"));
  check "equality of lists" "calls(fs.read_text) == [\"settings.json\"]"
    (Eq (Call (Ident "calls", [Proj (Ident "fs", "read_text")]),
      List [String "settings.json"]));
  check "equality as argument" "f(a == b)"
    (Call (Ident "f", [Eq (Ident "a", Ident "b")]));
  check "equality in struct" "{ ok: x == y }"
    (Struct [Field ("ok", Eq (Ident "x", Ident "y"))]);
  check_error "equality is non-associative" "a == b == c";
  check_error "equality missing right operand" "a ==";
  (* Newlines are not significant, so a parenthesised expression on the next
     line is an argument: here the lambda's body is the call x(1). *)
  check "newline before paren is a call" "x -> x\n(1)"
    (Lambda (["x"], Call (Ident "x", [Num "1"])));
  check "newline before paren in struct is a call" "{ a = f\n(x) }"
    (Struct [Local ("a", Call (Ident "f", [Ident "x"]))]);
  check "concat and addition share a level" "a ++ b + c"
    (Add (Concat (Ident "a", Ident "b"), Ident "c"));
  check "arrow is right-associative" "x -> y -> x"
    (Lambda (["x"], Lambda (["y"], Ident "x")));
  check "empty list" "[]"
    (List []);
  check "list of expressions" "[1, x, person.name, \"ok\"]"
    (List [
      Num "1";
      Ident "x";
      Proj (Ident "person", "name");
      String "ok";
    ]);
  check "nested lists" "[[], [1, 2]]"
    (List [
      List [];
      List [Num "1"; Num "2"];
    ]);

  check "some simple type" "some(Int)"
    (Some_val (Type_ident "Int"));
  check "some type application" "some(Result(Int, String))"
    (Some_val (Type_apply ("Result", [
      Type_ident "Int";
      Type_ident "String";
    ])));
  check "some record type" "some({ name: String, age: Int })"
    (Some_val (Type_record [
      ("name", Type_ident "String");
      ("age", Type_ident "Int");
    ]));
  check "some nested type" "some(Option({ value: Num }))"
    (Some_val (Type_apply ("Option", [
      Type_record [
        ("value", Type_ident "Num");
      ];
    ])));

  check "empty struct" "{}" (Struct []);
  check "simple struct" "{ answer: 42 }"
    (Struct [
      Field ("answer", Num "42");
    ]);
  check "nested struct" "{ answer: 42, config: { retries: 3 } }"
    (Struct [
      Field ("answer", Num "42");
      Field ("config", Struct [
        Field ("retries", Num "3");
      ]);
    ]);
  check "struct with identifier field" "{ answer: x }"
    (Struct [
      Field ("answer", Ident "x");
    ]);
  check "struct with projection field" "{ name: person.name }"
    (Struct [
      Field ("name", Proj (Ident "person", "name"));
    ]);
  check "local entry" "{ answer = 42 }"
    (Struct [
      Local ("answer", Num "42");
    ]);
  check "result entry" "{ <<answer }"
    (Struct [
      Result (Ident "answer");
    ]);
  check "locals and result" "{ x = 1, y = x, <<y }"
    (Struct [
      Local ("x", Num "1");
      Local ("y", Ident "x");
      Result (Ident "y");
    ]);
  check "trailing comma" "{ answer: 42, }"
    (Struct [
      Field ("answer", Num "42");
    ]);
  check "trailing comma after result" "{ x = 1, <<x, }"
    (Struct [
      Local ("x", Num "1");
      Result (Ident "x");
    ]);

  check "ensure" "{ ensure x == 1 }"
    (Struct [Ensure (Eq (Ident "x", Num "1"))]);
  check "ensure among entries" "{ x = f(1), ensure x == 2, ensure g(x), <<x }"
    (Struct [
      Local ("x", Call (Ident "f", [Num "1"]));
      Ensure (Eq (Ident "x", Num "2"));
      Ensure (Call (Ident "g", [Ident "x"]));
      Result (Ident "x");
    ]);
  check "ensure trailing comma" "{ ensure a == b, }"
    (Struct [Ensure (Eq (Ident "a", Ident "b"))]);
  check "ensure with lambda and calls" "{ ensure map(xs, x -> x + 1) == [2, 3] }"
    (Struct [
      Ensure (Eq (
        Call (Ident "map", [Ident "xs"; Lambda (["x"], Add (Ident "x", Num "1"))]),
        List [Num "2"; Num "3"]));
    ]);
  check "ensure on a struct" "{ ensure f(x) == { ok: 1 } }"
    (Struct [
      Ensure (Eq (Call (Ident "f", [Ident "x"]), Struct [Field ("ok", Num "1")]));
    ]);
  check_error "ensure needs an expression" "{ ensure }";
  check_error "ensure is not a name" "{ ensure: 1 }";
  check_error "ensure takes one expression" "{ ensure x y }";
  check_error "result must be last" "{ <<x, y = 1 }";
  check_error "result must be last with fields" "{ a: 1, <<a, b: 2 }";
  check_error "missing colon" "{ answer 42 }";
  check "list trailing comma" "[1, 2,]"
    (List [Num "1"; Num "2"]);
  check_error "type fields require lowercase names" "some({ Name: Int })";

  if !failures > 0 then exit 1 else print_endline "parser tests passed"
