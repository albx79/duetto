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
  check "empty struct" "{}" (Struct []);
  check "simple struct" "{ answer: 42 }"
    (Struct [ ("answer", Num "42") ]);
  check "nested struct" "{ answer: 42, config: { retries: 3 } }"
    (Struct [
      ("answer", Num "42");
      ("config", Struct [ ("retries", Num "3") ]);
    ]);
  check "trailing comma" "{ answer: 42, }"
    (Struct [ ("answer", Num "42") ]);
  check_error "field value must be num or struct" "{ answer: x }";
  check_error "missing colon" "{ answer 42 }";

  if !failures > 0 then exit 1 else print_endline "parser tests passed"
