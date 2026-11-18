module L = Duetto.Lexer

open Duetto.Tokens

let show = function
  | NUM n -> Printf.sprintf "NUM %S" n
  | STRING s -> Printf.sprintf "STRING %S" s
  | LABEL l -> "LABEL " ^ l
  | LIDENT x -> "LIDENT " ^ x
  | UIDENT x -> "UIDENT " ^ x
  | TYPE_VAR x -> "TYPE_VAR " ^ x
  | SPEC t -> Printf.sprintf "SPEC %S" (Duetto.Spec_title.to_string t)
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
  | EVERY -> "EVERY" | DOUBLE -> "DOUBLE" | CARET -> "CARET"
  | LT -> "LT" | LE -> "LE" | GT -> "GT" | GE -> "GE" | EQUIV -> "EQUIV"
  | EOF -> "EOF"

let tokens src =
  let lexbuf = Lexing.from_string src in
  let rec go acc =
    match L.token lexbuf with
    | EOF -> List.rev acc
    | t -> go (t :: acc)
  in
  go []

let failures = ref 0

(* An expected SPEC token, written as its title reads, with backticks around
   marks. Tokens are compared through [show], which ignores positions, and a
   title's text determines its segments, since text has no backticks. *)
let spec title =
  SPEC [ (Duetto.Spec_title.Text title, Lexing.dummy_pos, Lexing.dummy_pos) ]

let check name src expected =
  let actual = tokens src in
  if List.map show actual <> List.map show expected then begin
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
  check "identifier character classes" "foo_bar2 _x 'foo_bar Foo2Bar"
    [ LIDENT "foo_bar2"; LIDENT "_x"; LABEL "foo_bar"; UIDENT "Foo2Bar" ];
  check_error "lident cannot contain uppercase" "readFile"
    "Unexpected character 'F' at :1:5";
  check_error "lident uppercase after underscore" "x = read_File"
    "Unexpected character 'F' at :1:10";
  check_error "lident cannot start with underscore then uppercase" "_Foo"
    "Unexpected character 'F' at :1:2";
  check_error "keyword prefix does not split a name" "doThing"
    "Unexpected character 'T' at :1:3";
  check_error "label cannot contain uppercase" "'notFound"
    "Unexpected character 'F' at :1:5";
  check "comparison operators" "< <= > >= ~~ << -> == ?"
    [ LT; LE; GT; GE; EQUIV; RESULT; ARROW; EQEQ; QUESTION ];
  check "comparison operators without spaces" "o?a<=b"
    [ LIDENT "o"; QUESTION; LIDENT "a"; LE; LIDENT "b" ];
  check "double and pins" "double ^x doubled"
    [ DOUBLE; CARET; LIDENT "x"; LIDENT "doubled" ];
  check "type variables" "?A ?Key"
    [ TYPE_VAR "A"; TYPE_VAR "Key" ];
  check "question mark apart from a type name" "? A ?a"
    [ QUESTION; UIDENT "A"; QUESTION; LIDENT "a" ];
  check_error "uident cannot contain underscore" "Foo_Bar"
    "Unexpected character '_' at :1:4";
  check_error "type variable cannot contain underscore" "?Foo_Bar"
    "Unexpected character '_' at :1:5";
  check_error "type variable underscore before lowercase" "some(?Key_type)"
    "Unexpected character '_' at :1:10";
  check "operators" "-> == = << .. . ++ + - * / % : | ?"
    [ ARROW; EQEQ; EQUAL; RESULT; DOTDOT; DOT; CONCAT; PLUS; MINUS;
      TIMES; DIV; MOD; COLON; BAR; QUESTION ];
  check "comments" "x # a comment\ny" [ LIDENT "x"; LIDENT "y" ];
  check "reserved tokens inside a comment" "x # see #! #[ ]# #_\ny"
    [ LIDENT "x"; LIDENT "y" ];
  check "comment starting with two hashes" "x ##[ y\nz"
    [ LIDENT "x"; LIDENT "z" ];
  check "bracket then spaced comment" "[1] # note"
    [ LBRACKET; NUM "1"; RBRACKET ];
  check_error "reserved #! at end of line" "x #!"
    "The token '#!' at :1:3 is reserved for future use";
  check_error "reserved #! before text" "#!/usr/bin/env duetto\nx"
    "The token '#!' at :1:1 is reserved for future use";
  check_error "reserved #[ before text" "x\n  #[ foo"
    "The token '#[' at :2:3 is reserved for future use";
  check_error "reserved #_ before text" "#_x"
    "The token '#_' at :1:1 is reserved for future use";
  check_error "reserved ]# at end of line" "x ]#"
    "The token ']#' at :1:3 is reserved for future use";
  (* ]# is reserved wherever it appears, even where it could be read as ]
     followed by a comment. *)
  check_error "reserved ]# after a list" "[1]# note"
    "The token ']#' at :1:3 is reserved for future use";
  check "spec title" "spec the answer is 42 {\n  ensure x == 42,\n}"
    [ spec "the answer is 42"; LBRACE; ENSURE; LIDENT "x"; EQEQ; NUM "42";
      COMMA; RBRACE ];
  check "spec title whitespace is normalised" "spec  a\t b\n\n  c  {}"
    [ spec "a b c"; LBRACE; RBRACE ];
  check "spec title keeps # and unbalanced brackets"
    "spec [0, 1) is half-open # not a comment {}"
    [ spec "[0, 1) is half-open # not a comment"; LBRACE; RBRACE ];
  check "law spec title" "spec `Ordering` is symmetric {}"
    [ spec "`Ordering` is symmetric"; LBRACE; RBRACE ];
  check "law spec title with two marks" "spec  `Ordering`   agrees\n with `Eq` {}"
    [ spec "`Ordering` agrees with `Eq`"; LBRACE; RBRACE ];
  check "qualified mark" "spec `std.Ordering` is total {}"
    [ spec "`std.Ordering` is total"; LBRACE; RBRACE ];
  check "title of marks only" "spec `Monoid` {}"
    [ spec "`Monoid`"; LBRACE; RBRACE ];
  check "mark followed by punctuation" "spec `Ordering`'s laws {}"
    [ spec "`Ordering`'s laws"; LBRACE; RBRACE ];
  check "every" "every(Ordering(?A))"
    [ EVERY; LPAREN; UIDENT "Ordering"; LPAREN; TYPE_VAR "A"; RPAREN; RPAREN ];
  check "spec title keeps quotes and labels" "spec it's \"quoted\" 'eq {}"
    [ spec "it's \"quoted\" 'eq"; LBRACE; RBRACE ];
  check "spec prefix is an identifier" "specs" [ LIDENT "specs" ];
  check "keywords as labels" "'case 'spec 'do"
    [ LABEL "case"; LABEL "spec"; LABEL "do" ];
  check "rigid row" "some({ name: String, ..?R })"
    [ SOME; LPAREN; LBRACE; LIDENT "name"; COLON; UIDENT "String"; COMMA;
      DOTDOT; TYPE_VAR "R"; RBRACE; RPAREN ];
  check "case" "case x { 'a -> 1, 'b -> 2 }"
    [ CASE; LIDENT "x"; LBRACE; LABEL "a"; ARROW; NUM "1"; COMMA;
      LABEL "b"; ARROW; NUM "2"; RBRACE ];
  check "block" "{ tmp = f(x), <<tmp + 1 }"
    [ LBRACE; LIDENT "tmp"; EQUAL; LIDENT "f"; LPAREN; LIDENT "x"; RPAREN;
      COMMA; RESULT; LIDENT "tmp"; PLUS; NUM "1"; RBRACE ];
  check "call" "ord.compare(a, f(),)"
    [ LIDENT "ord"; DOT; LIDENT "compare"; LPAREN; LIDENT "a"; COMMA;
      LIDENT "f"; LPAREN; RPAREN; COMMA; RPAREN ];
  check "list and projection" "[p.name, xs]"
    [ LBRACKET; LIDENT "p"; DOT; LIDENT "name"; COMMA; LIDENT "xs";
      RBRACKET ];
  check "numeric exponent" "1e3 2E+4 5e-6"
    [ NUM "1e3"; NUM "2E+4"; NUM "5e-6" ];
  check "decimal point" "3.14 0.5 1.5e-3"
    [ NUM "3.14"; NUM "0.5"; NUM "1.5e-3" ];
  check "range is not a decimal" "1..2"
    [ NUM "1"; DOTDOT; NUM "2" ];
  check "big numeric literal" "99999999999999999999"
    [ NUM "99999999999999999999" ];
  check_error "unterminated string" "x = \"abc"
    "Unterminated string literal starting at :1:5";
  check_error "invalid escape" {|"a\qb"|}
    "Invalid escape sequence '\\q' at :1:3";
  check_error "unexpected character" "x\n  @"
    "Unexpected character '@' at :2:3";
  (* Columns count characters, not bytes. *)
  check_error "column after a non-ASCII string" "x: \"é\", y: @"
    "Unexpected character '@' at :1:12";
  check_error "column after three-byte characters" "\"日本\", @"
    "Unexpected character '@' at :1:7";
  check_error "column after a non-ASCII spec title" "spec café { @ }"
    "Unexpected character '@' at :1:13";
  check_error "mark column after a non-ASCII title" "spec é `bad` {}"
    "The mark `bad` at :1:8 is not an interface name: a mark is a type name, such as `Ordering` or `m.Ordering`";
  check_error "column on the line after a non-ASCII title" "spec é\nü {\n  @ }"
    "Unexpected character '@' at :3:3";
  check_error "non-ASCII character" "x = é"
    "Unexpected character 'é' at :1:5";
  check_error "four-byte character" "x = 😀"
    "Unexpected character '😀' at :1:5";
  check_error "invalid UTF-8 byte" "x = \xff"
    "The byte 0xFF at :1:5 is not valid UTF-8 (source files must be UTF-8)";
  check_error "lone continuation byte" "\x80"
    "The byte 0x80 at :1:1 is not valid UTF-8 (source files must be UTF-8)";
  check_error "truncated UTF-8 sequence" "x\xc3"
    "The byte 0xC3 at :1:2 is not valid UTF-8 (source files must be UTF-8)";
  check_error "control character" "\x01"
    "Unexpected character '\\x01' at :1:1";
  check_error "non-ASCII invalid escape" "\"\\é\""
    "Invalid escape sequence '\\é' at :1:2";
  check "non-ASCII string" "\"café 日本 😀\"" [ STRING "café 日本 😀" ];
  check_error "line after multi-line title" "spec a\nb\n{ }\n  !"
    "Unexpected character '!' at :4:3";
  check_error "spec without title" "spec{}"
    "The spec at :1:1 has no title";
  check_error "spec with blank title" "spec \n  {}"
    "The spec at :1:1 has no title";
  check_error "spec as a local" "{ spec = 1 }"
    "'spec' at :1:3 is a keyword and cannot be used as a name";
  check_error "spec as a field" "{ spec: 1 }"
    "'spec' at :1:3 is a keyword and cannot be used as a name";
  check_error "spec as a field, spaced colon" "{ spec : 1 }"
    "'spec' at :1:3 is a keyword and cannot be used as a name";
  check_error "spec as an argument" "f(spec)"
    "'spec' at :1:3 is a keyword and cannot be used as a name";
  check_error "spec at end of input" "x = spec"
    "'spec' at :1:5 is a keyword and cannot be used as a name";
  check_error "spec compared" "ensure spec == 1"
    "'spec' at :1:8 is a keyword and cannot be used as a name";
  check_error "spec on a later line" "x = 1,\n  spec = 2"
    "'spec' at :2:3 is a keyword and cannot be used as a name";
  check_error "spec before a real spec" "spec = 1,\nspec real {}"
    "'spec' at :1:1 is a keyword and cannot be used as a name";
  check "spec prefix with underscore is an identifier" "spec_x"
    [ LIDENT "spec_x" ];
  check_error "closing brace in spec title" "x = 1,\nspec a } b {}"
    "A spec title cannot contain '}', at :2:8 (is the '{' after the title missing?)";
  check_error "missing brace after spec title" "spec a\n  ensure x == 1,\n}"
    "A spec title cannot contain '}', at :3:1 (is the '{' after the title missing?)";
  check_error "unclosed mark" "spec laws of `Ordering {}"
    "The '`' at :1:14 in a spec title is not closed";
  check_error "empty mark" "spec `` is empty {}"
    "The mark `` at :1:6 is not an interface name: a mark is a type name, such as `Ordering` or `m.Ordering`";
  check_error "lowercase mark" "spec `ordering` is total {}"
    "The mark `ordering` at :1:6 is not an interface name: a mark is a type name, such as `Ordering` or `m.Ordering`";
  check_error "mark with spaces" "spec `Ordering is` total {}"
    "The mark `Ordering is` at :1:6 is not an interface name: a mark is a type name, such as `Ordering` or `m.Ordering`";
  check_error "mark ending with a dot" "spec `m.` is odd {}"
    "The mark `m.` at :1:6 is not an interface name: a mark is a type name, such as `Ordering` or `m.Ordering`";
  check_error "mark position on a later line" "spec laws\n  of `bad` {}"
    "The mark `bad` at :2:6 is not an interface name: a mark is a type name, such as `Ordering` or `m.Ordering`";

  if !failures > 0 then exit 1 else print_endline "lexer tests passed"
