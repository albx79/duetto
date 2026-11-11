open Duetto.Parser

let show = function
  | NUM n -> Printf.sprintf "NUM %S" n
  | STRING s -> Printf.sprintf "STRING %S" s
  | LABEL l -> "LABEL " ^ l
  | LIDENT x -> "LIDENT " ^ x
  | UIDENT x -> "UIDENT " ^ x
  | SPEC t -> Printf.sprintf "SPEC %S" t
  | CASE -> "CASE" | SOME -> "SOME" | ENSURE -> "ENSURE" | DO -> "DO"
  | ARROW -> "ARROW" | EQEQ -> "EQEQ" | RESULT -> "RESULT"
  | DOTDOT -> "DOTDOT" | CONCAT -> "CONCAT"
  | PLUS -> "PLUS" | MINUS -> "MINUS" | TIMES -> "TIMES"
  | DIV -> "DIV" | MOD -> "MOD"
  | EQUAL -> "EQUAL" | COLON -> "COLON" | COMMA -> "COMMA"
  | DOT -> "DOT" | BAR -> "BAR" | QUESTION -> "QUESTION"
  | LPAREN -> "LPAREN" | RPAREN -> "RPAREN"
  | LBRACE -> "LBRACE" | RBRACE -> "RBRACE"
  | LBRACKET -> "LBRACKET" | RBRACKET -> "RBRACKET"
  | EOF -> "EOF"

let tokens src =
  let lexbuf = Lexing.from_string src in
  let rec go acc =
    match Duetto.Lexer.token lexbuf with
    | EOF -> List.rev acc
    | t -> go (t :: acc)
  in
  go []

let failures = ref 0

let check name src expected =
  let actual = tokens src in
  if actual <> expected then begin
    incr failures;
    Printf.printf "FAIL %s\n  expected: %s\n  actual:   %s\n" name
      (String.concat " " (List.map show expected))
      (String.concat " " (List.map show actual))
  end

let check_error name src expected =
  match tokens src with
  | _ ->
      incr failures;
      Printf.printf "FAIL %s: expected a lexical error\n" name
  | exception Duetto.Diagnostic.Error e ->
      let actual = Duetto.Diagnostic.string_of_error e in
      if actual <> expected then begin
        incr failures;
        Printf.printf "FAIL %s\n  expected: %s\n  actual:   %s\n" name
          expected actual
      end

let () =
  check "literals" {|42 "Hello, Ada" 'true|}
    [ NUM "42"; STRING "Hello, Ada"; LABEL "true" ];
  check "string escapes" {|"a\"b\\c\nd\te"|} [ STRING "a\"b\\c\nd\te" ];
  check "names and keywords" "x some_thing case some ensure Int Ordering"
    [ LIDENT "x"; LIDENT "some_thing"; CASE; SOME; ENSURE;
      UIDENT "Int"; UIDENT "Ordering" ];
  check "identifier character classes" "fooBar 'foo_bar"
    [ LIDENT "foo"; UIDENT "Bar"; LABEL "foo_bar" ];
  check_error "uident cannot contain underscore" "Foo_Bar"
    "Unexpected character '_' at :1:4";
  check "operators" "-> == = << .. . ++ + - * / % : | ?"
    [ ARROW; EQEQ; EQUAL; RESULT; DOTDOT; DOT; CONCAT; PLUS; MINUS;
      TIMES; DIV; MOD; COLON; BAR; QUESTION ];
  check "comments" "x # a comment\ny" [ LIDENT "x"; LIDENT "y" ];
  check "spec title" "spec the answer is 42 {\n  ensure x == 42,\n}"
    [ SPEC "the answer is 42"; LBRACE; ENSURE; LIDENT "x"; EQEQ; NUM "42";
      COMMA; RBRACE ];
  check "spec without title" "spec{}" [ SPEC ""; LBRACE; RBRACE ];
  check "spec prefix is an identifier" "specs" [ LIDENT "specs" ];
  check "rigid row" "some({ name: String, ..?R })"
    [ SOME; LPAREN; LBRACE; LIDENT "name"; COLON; UIDENT "String"; COMMA;
      DOTDOT; QUESTION; UIDENT "R"; RBRACE; RPAREN ];
  check "case" "case x { 'a -> 1, 'b -> 2 }"
    [ CASE; LIDENT "x"; LBRACE; LABEL "a"; ARROW; NUM "1"; COMMA;
      LABEL "b"; ARROW; NUM "2"; RBRACE ];
  check "block" "{ tmp = f(x), <<tmp + 1 }"
    [ LBRACE; LIDENT "tmp"; EQUAL; LIDENT "f"; LPAREN; LIDENT "x"; RPAREN;
      COMMA; RESULT; LIDENT "tmp"; PLUS; NUM "1"; RBRACE ];
  check "list and projection" "[p.name, xs]"
    [ LBRACKET; LIDENT "p"; DOT; LIDENT "name"; COMMA; LIDENT "xs";
      RBRACKET ];
  check "numeric exponent" "1e3 2E+4 5e-6"
    [ NUM "1e3"; NUM "2E+4"; NUM "5e-6" ];
  check "big numeric literal" "99999999999999999999"
    [ NUM "99999999999999999999" ];
  check_error "unterminated string" "x = \"abc"
    "Unterminated string literal starting at :1:5";
  check_error "invalid escape" {|"a\qb"|}
    "Invalid escape sequence '\\q' at :1:3";
  check_error "unexpected character" "x\n  @"
    "Unexpected character '@' at :2:3";
  check_error "line after multi-line title" "spec a\nb\n{ }\n  !"
    "Unexpected character '!' at :4:3";

  if !failures > 0 then exit 1 else print_endline "lexer tests passed"
