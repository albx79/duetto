open Duetto.Ast

let parse src =
  let lexbuf = Lexing.from_string src in
  Duetto.Parse.parse lexbuf

let failures = ref 0

let check name src expected =
  match parse src with
  | actual when actual = expected -> ()
  | actual ->
      incr failures;
      Printf.printf "FAIL %s\n  expected: %s\n  actual:   %s\n" name
        (Duetto.Ast.show_expr expected)
        (Duetto.Ast.show_expr actual)
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

let () =
  check "num literal" "42" (Num "42");
  check "identifier" "x" (Ident "x");
  check "projection" "person.name" (Proj (Ident "person", "name"));
  check "chained projection" "a.b.c"
    (Proj (Proj (Ident "a", "b"), "c"));
  check "some simple type" "some(Int)"
    (Some_val (Type_ident "Int"));
  check "some type application" "some(Result(Int, String))"
    (Some_val (Type_apply ("Result", [Type_ident "Int"; Type_ident "String"])));
  check "some record type" "some({ name: String, age: Int })"
    (Some_val (Type_record [
      ("name", Type_ident "String");
      ("age", Type_ident "Int");
    ]));
  check "some nested type" "some(Option({ value: Num }))"
    (Some_val (Type_apply ("Option", [
      Type_record [ ("value", Type_ident "Num") ];
    ])));
  check "empty struct" "{}" (Struct []);
  check "simple struct" "{ answer: 42 }"
    (Struct [ Field ("answer", Num "42") ]);
  check "nested struct" "{ answer: 42, config: { retries: 3 } }"
    (Struct [
      Field ("answer", Num "42");
      Field ("config", Struct [ Field ("retries", Num "3") ]);
    ]);
  check "struct with identifier field" "{ answer: x }"
    (Struct [ Field ("answer", Ident "x") ]);
  check "struct with projection field" "{ name: person.name }"
    (Struct [ Field ("name", Proj (Ident "person", "name")) ]);
  check "local entry" "{ answer = 42 }"
    (Struct [ Local ("answer", Num "42") ]);
  check "result entry" "{ <<answer }"
    (Struct [ Result (Ident "answer") ]);
  check "locals and result" "{ x = 1, y = x, <<y }"
    (Struct [
      Local ("x", Num "1");
      Local ("y", Ident "x");
      Result (Ident "y");
    ]);
  check "trailing comma" "{ answer: 42, }"
    (Struct [ Field ("answer", Num "42") ]);
  check "trailing comma after result" "{ x = 1, <<x, }"
    (Struct [ Local ("x", Num "1"); Result (Ident "x") ]);
  check_error "result must be last" "{ <<x, y = 1 }";
  check_error "result must be last with fields" "{ a: 1, <<a, b: 2 }";
  check_error "missing colon" "{ answer 42 }";
  check_error "type fields require lowercase names" "some({ Name: Int })";

  if !failures > 0 then exit 1 else print_endline "parser tests passed"
