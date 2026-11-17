module A = Duetto.Ast.Unit
open A

let failures = ref 0

let parse_expr src = Duetto.Parse.parse_expr_unit (Lexing.from_string src)
let parse_file src = Duetto.Parse.parse_unit (Lexing.from_string src)

(* [parse] must succeed and give [expected]. *)
let expect_tree parse name src expected =
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

(* [parse] must fail, with the message [expected] unless it is "". *)
let expect_error parse name src expected =
  match parse src with
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

let check = expect_tree parse_expr
let check_error name src = expect_error parse_expr name src ""
let check_file = expect_tree parse_file
let check_file_error = expect_error parse_file

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

  (* Records, blocks, spec bodies and files allow different entries
     (spec, sections 3.2 and 3.3). *)
  check "record with every record entry" "{ a: 1, b = 2, T: Num, U = Num, ensure b == 2, do f(), c }"
    (Record [
      Field ("a", Num "1");
      Local ("b", Num "2");
      Type_field ("T", [], Type_ref ([], "Num"));
      Type_local ("U", [], Type_ref ([], "Num"));
      Ensure (Eq (Ident "b", Num "2"));
      Do (Call (Ident "f", []));
      Field ("c", Ident "c");
    ]);
  check "block with every block entry" "{ b = 2, U = Num, ensure b == 2, do f(), <<b }"
    (Block ([
      Local ("b", Num "2");
      Type_local ("U", [], Type_ref ([], "Num"));
      Ensure (Eq (Ident "b", Num "2"));
      Do (Call (Ident "f", []));
    ], Ident "b"));
  check_file_error "field in a block" "x: {\n  a = 1,\n  b: 2,\n  <<a\n}"
    "The field 'b' at :3:3 is in a block: a brace group that ends with '<<' cannot have fields (use 'b = ...' for a local)";
  check_file_error "punned name in a block" "x: { a = 1, a, <<a }"
    "The field 'a' at :1:13 is in a block: a brace group that ends with '<<' cannot have fields (use 'a = ...' for a local)";
  check_file_error "public type in a block" "x: { T: Num, <<1 }"
    "The public type 'T' at :1:6 is in a block: a brace group that ends with '<<' cannot have public types (use 'T = ...' for a private type)";
  check_file_error "punned type in a block" "x: { m.Bool, <<1 }"
    "The public type 'Bool' at :1:6 is in a block: a brace group that ends with '<<' cannot have public types (use 'Bool = ...' for a private type)";
  check_file "file with every file entry" "a: 1, b = 2, T: Num, U = Num, ensure b == 2, spec s { ensure a == 1 }, c"
    (Record [
      Field ("a", Num "1");
      Local ("b", Num "2");
      Type_field ("T", [], Type_ref ([], "Num"));
      Type_local ("U", [], Type_ref ([], "Num"));
      Ensure (Eq (Ident "b", Num "2"));
      Spec ([Title_text "s"], [Ensure (Eq (Ident "a", Num "1"))]);
      Field ("c", Ident "c");
    ]);
  check_file_error "result at file level" "x = 1,\n<<x"
    "The '<<' at :2:1 is at file level: a file is a static struct and has no result";
  check_file_error "do at file level" "x: 1,\n  do f()"
    "The 'do' at :2:3 is at file level: a file is a static struct and performs no actions";
  check_file "private types in a spec" "spec orderings { NumOrd = Ordering(Num), natural = some(NumOrd), ensure natural.compare(1, 1) == 'eq }"
    (Record [
      Spec ([Title_text "orderings"], [
        Type_local ("NumOrd", [], Type_apply ([], "Ordering", [Type_ref ([], "Num")]));
        Local ("natural", Some_val (Type_ref ([], "NumOrd")));
        Ensure (Eq (Call (Proj (Ident "natural", "compare"), [Num "1"; Num "1"]), Label "eq"));
      ]);
    ]);
  check_file_error "no public types in a spec" "spec s { T: Num }" "";
  check_file_error "no do in a spec" "spec s { do f() }" "";
  check_file_error "error names a string token" "x: \"abc\" \"def\""
    "Unexpected token '\"def\"' at :1:10";
  check_file_error "error names a spec token" "x: 1 spec title {}"
    "Unexpected token 'spec title' at :1:6";
  check_file_error "error names a punctuation token" "x: (1"
    "Unexpected end of input at :1:6";
  check_file_error "error names a label token" "x: 1 'a"
    "Unexpected token ''a' at :1:6";
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
      { pattern = Record_pattern [("num", Binder "num")]; body = Ident "num" };
      { pattern = Record_pattern [("add", Binder "add")];
        body = Add (Call (Ident "eval", [Proj (Ident "add", "l")]),
                    Call (Ident "eval", [Proj (Ident "add", "r")])) };
    ]));
  check "record patterns" "case r { {} -> 0, { a, b } -> 1, { a, } -> 2, { a, b, .. } -> 3, { .. } -> 4 }"
    (Case (Ident "r", [
      { pattern = Record_pattern []; body = Num "0" };
      { pattern = Record_pattern [("a", Binder "a"); ("b", Binder "b")]; body = Num "1" };
      { pattern = Record_pattern [("a", Binder "a")]; body = Num "2" };
      { pattern = Open_record_pattern [("a", Binder "a"); ("b", Binder "b")]; body = Num "3" };
      { pattern = Open_record_pattern []; body = Num "4" };
    ]));
  check "case branch with a block" "case x { 'a -> { y = 1, <<y } }"
    (Case (Ident "x", [
      { pattern = Label_pattern "a"; body = Block ([Local ("y", Num "1")], Ident "y") };
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
  check "binder pattern" "case x { 'a -> 1, y -> 2 }"
    (Case (Ident "x", [
      { pattern = Label_pattern "a"; body = Num "1" };
      { pattern = Binder "y"; body = Num "2" };
    ]));
  check_error "pattern is not an expression" "case x { f(y) -> 1 }";
  check_error "open pattern ends with .." "case x { { .., a } -> 1 }";
  check_error "no comma after .." "case x { { a, .., } -> 1 }";
  check "literal and sub-patterns" "case x { 0 -> 'zero, \"one\" -> 'one, { a: 1, b: { c }, .. } -> 'rec, n -> 'other }"
    (Case (Ident "x", [
      { pattern = Num_pattern "0"; body = Label "zero" };
      { pattern = String_pattern "one"; body = Label "one" };
      { pattern = Open_record_pattern [
          ("a", Num_pattern "1");
          ("b", Record_pattern [("c", Binder "c")]);
        ]; body = Label "rec" };
      { pattern = Binder "n"; body = Label "other" };
    ]));
  check "pinned and typed patterns" "case x { ^expected -> 'same, { ok: some(Num) } -> 'num, other -> 'other }"
    (Case (Ident "x", [
      { pattern = Pinned "expected"; body = Label "same" };
      { pattern = Record_pattern [("ok", Some_pattern (Type_ref ([], "Num")))]; body = Label "num" };
      { pattern = Binder "other"; body = Label "other" };
    ]));
  check "renaming a field" "case r { { err: e } -> e }"
    (Case (Ident "r", [{ pattern = Record_pattern [("err", Binder "e")]; body = Ident "e" }]));
  check_error "pin needs a value name" "case x { ^Foo -> 1 }";
  check_error "pin is not an expression" "^x";
  check_error "no expressions in patterns" "case x { a + 1 -> 1 }";

  (* Comparisons under an ordering (spec, section 6.2). *)
  check "comparison" "ord ? a < b" (Compare (Ident "ord", Less, Ident "a", Ident "b"));
  check "comparison operators" "[o ? a <= b, o ? a > b, o ? a >= b, o ? a ~~ b]"
    (List [
      Compare (Ident "o", Less_or_equal, Ident "a", Ident "b");
      Compare (Ident "o", Greater, Ident "a", Ident "b");
      Compare (Ident "o", Greater_or_equal, Ident "a", Ident "b");
      Compare (Ident "o", Equivalent, Ident "a", Ident "b");
    ]);
  check "ordering is a projection" "people.by_name ? a < b"
    (Compare (Proj (Ident "people", "by_name"), Less, Ident "a", Ident "b"));
  check "ordering is a call" "by(key) ? a < b"
    (Compare (Call (Ident "by", [Ident "key"]), Less, Ident "a", Ident "b"));
  check "operands bind as arithmetic" "ord ? x + 1 < y * 2"
    (Compare (Ident "ord", Less, Add (Ident "x", Num "1"), Mul (Ident "y", Num "2")));
  check "ordering binds tighter than arithmetic" "a + ord ? x < y"
    (Add (Ident "a", Compare (Ident "ord", Less, Ident "x", Ident "y")));
  check "comparison as a lambda body" "x -> ord ? x < 1"
    (Lambda (["x"], Compare (Ident "ord", Less, Ident "x", Num "1")));
  check "comparison as a case scrutinee" "case ord ? a < b { 'true -> 1, 'false -> 0 }"
    (Case (Compare (Ident "ord", Less, Ident "a", Ident "b"), [
      { pattern = Label_pattern "true"; body = Num "1" };
      { pattern = Label_pattern "false"; body = Num "0" };
    ]));
  check "parenthesised comparison compared" "(ord ? a < b) == 'true"
    (Eq (Compare (Ident "ord", Less, Ident "a", Ident "b"), Label "true"));
  check_file "law spec" "spec `Ordering` agrees with `std.Eq` { ord = every(Ordering(?A)), eq = every(std.Eq(A)), x = some(A), ensure 1 == 1 }"
    (Record [Spec (
      [Title_mark ([], "Ordering"); Title_text " agrees with "; Title_mark (["std"], "Eq")],
      [
        Local ("ord", Every (Type_apply ([], "Ordering", [Type_var "A"])));
        Local ("eq", Every (Type_apply (["std"], "Eq", [Type_ref ([], "A")])));
        Local ("x", Some_val (Type_ref ([], "A")));
        Ensure (Eq (Num "1", Num "1"));
      ])]);
  check "every" "every(Ordering(?A))" (Every (Type_apply ([], "Ordering", [Type_var "A"])));
  check_error "every is not a pattern" "case x { every(Num) -> 1 }";
  check_error "every needs a type" "every(x)";
  check_file_error "law spec in a nested struct" "m: { spec `Ordering` is total {} }"
    "The spec '`Ordering` is total' at :1:6 is inside a nested struct; specs are allowed only at file level";
  check_file "comparison in a spec" "spec strings { ensure lexicographic ? \"bar\" < \"foo\" }"
    (Record [Spec ([Title_text "strings"], [
      Ensure (Compare (Ident "lexicographic", Less, String "bar", String "foo"));
    ])]);
  check_file_error "comparison needs an ordering" "x: a < b"
    "Unexpected '<' at :1:6: a comparison names its ordering, as in 'ord ? a < b', and comparisons cannot be chained";
  check_file_error "comparisons do not chain" "x: ord ? a < b <= c"
    "Unexpected '<=' at :1:16: a comparison names its ordering, as in 'ord ? a <= b', and comparisons cannot be chained";
  check_error "comparison is non-associative with ==" "ord ? a < b == 'true";
  check_error "ordering needs a comparison" "ord ? a";
  check_error "== is not a comparison under an ordering" "ord ? a == b";

  (* Doubles (spec, section 11). *)
  check "double" "double { read_text(\"a.cfg\") << \"content\" }"
    (Double [{ stub_name = "read_text"; arguments = [String_pattern "a.cfg"];
               responses = [String "content"] }]);
  check "double with several stubs" "double { read_text(\"ok.cfg\") << { ok: \"content\" }, read_text(\"a.cfg\") << { not_found: { path: \"a.cfg\" } }, }"
    (Double [
      { stub_name = "read_text"; arguments = [String_pattern "ok.cfg"];
        responses = [Record [Field ("ok", String "content")]] };
      { stub_name = "read_text"; arguments = [String_pattern "a.cfg"];
        responses = [Record [Field ("not_found", Record [Field ("path", String "a.cfg")])]] };
    ]);
  check "response chain" "double { fetch(\"a\") << 'timeout << 'timeout << { ok: \"data\" } }"
    (Double [{ stub_name = "fetch"; arguments = [String_pattern "a"];
               responses = [Label "timeout"; Label "timeout"; Record [Field ("ok", String "data")]] }]);
  check "stub argument patterns" "double { f(some(String), path, ^cfg, { id: 1, .. }, 'a, 2) << path }"
    (Double [{ stub_name = "f";
               arguments = [
                 Some_pattern (Type_ref ([], "String"));
                 Binder "path";
                 Pinned "cfg";
                 Open_record_pattern [("id", Num_pattern "1")];
                 Label_pattern "a";
                 Num_pattern "2";
               ];
               responses = [Ident "path"] }]);
  check "stub without arguments" "double { now() << 1 << 2 }"
    (Double [{ stub_name = "now"; arguments = []; responses = [Num "1"; Num "2"] }]);
  check "response is any expression" "double { f(x) << { y = x + 1, <<y } << (z -> z) << g(x) }"
    (Double [{ stub_name = "f"; arguments = [Binder "x"];
               responses = [
                 Block ([Local ("y", Add (Ident "x", Num "1"))], Ident "y");
                 Lambda (["z"], Ident "z");
                 Call (Ident "g", [Ident "x"]);
               ] }]);
  check "double in a spec" "{ fs = double { read_text(p) << p }, <<fs }"
    (Block ([
      Local ("fs", Double [{ stub_name = "read_text"; arguments = [Binder "p"];
                             responses = [Ident "p"] }]);
    ], Ident "fs"));
  check_error "double needs a stub" "double {}";
  check_error "stub needs a response" "double { f(1) }";
  check_error "response needs an expression" "double { f(1) << }";
  check_error "stub needs parentheses" "double { f << 1 }";
  check_error "stubs need commas" "double { f(1) << 1 g(2) << 2 }";
  check_error "no fields in a double" "double { f: 1 }";
  check_error "stub arguments are patterns" "double { f(a + 1) << 1 }";
  check_error "double is a keyword" "{ double = 1 }";
  check_error "branches need commas" "case x { 'a -> 1 'b -> 2 }";

  check_file "spec" "spec it works { ensure f(1) == 2 }"
    (Record [Spec ([Title_text "it works"], [Ensure (Eq (Call (Ident "f", [Num "1"]), Num "2"))])]);
  check_file "spec with locals" "spec adds { x = f(1), y = x + 1, ensure y == 3, }"
    (Record [
      Spec ([Title_text "adds"], [
        Local ("x", Call (Ident "f", [Num "1"]));
        Local ("y", Add (Ident "x", Num "1"));
        Ensure (Eq (Ident "y", Num "3"));
      ]);
    ]);
  check_file "empty spec" "spec nothing yet {}" (Record [Spec ([Title_text "nothing yet"], [])]);
  check_file "specs among fields" "f: x -> x,\nspec identity { ensure f(1) == 1 },\ng: 2,"
    (Record [
      Field ("f", Lambda (["x"], Ident "x"));
      Spec ([Title_text "identity"], [Ensure (Eq (Call (Ident "f", [Num "1"]), Num "1"))]);
      Field ("g", Num "2");
    ]);
  check_file "spec with nested struct" "spec s { r = { a: 1 }, ensure r.a == 1 }"
    (Record [
      Spec ([Title_text "s"], [
        Local ("r", Record [Field ("a", Num "1")]);
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
    (Lambda (["x"], Block ([
      Local ("y", Ident "x")], Ident "y")));
  check "projection" "person.name"
    (Proj (Ident "person", "name"));
  check "chained projection" "a.b.c"
    (Proj (Proj (Ident "a", "b"), "c"));
  check "arithmetic" "1 + 2"
    (Add (Num "1", Num "2"));
  check "mod operator" "7 % 3"
    (Mod (Num "7", Num "3"));
  check "mod precedence" "1 + 7 % 3"
    (Add (Num "1", Mod (Num "7", Num "3")));
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
    (Call (Ident "f", [Record [Field ("a", Num "1")]]));
  check "call in struct" "{ tmp = f(x), <<tmp + 1 }"
    (Block ([
      Local ("tmp", Call (Ident "f", [Ident "x"]))], Add (Ident "tmp", Num "1")));
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
    (Record [Field ("ok", Eq (Ident "x", Ident "y"))]);
  check_error "equality is non-associative" "a == b == c";
  check_error "equality missing right operand" "a ==";
  (* Newlines are not significant, so a parenthesised expression on the next
     line is an argument: here the lambda's body is the call x(1). *)
  check "newline before paren is a call" "x -> x\n(1)"
    (Lambda (["x"], Call (Ident "x", [Num "1"])));
  check "newline before paren in struct is a call" "{ a = f\n(x) }"
    (Record [Local ("a", Call (Ident "f", [Ident "x"]))]);
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
    (Some_val (Type_ref ([], "Int")));
  check "some qualified type" "some(m.Bool)"
    (Some_val (Type_ref (["m"], "Bool")));
  check "some deeply qualified type" "some(a.b.Bool)"
    (Some_val (Type_ref (["a"; "b"], "Bool")));
  check_error "type path ends with a type" "some(m.b)";
  check_error "no types inside types" "some(M.Bool)";
  check "some type application" "some(Result(Int, String))"
    (Some_val (Type_apply ([], "Result", [
      Type_ref ([], "Int");
      Type_ref ([], "String");
    ])));
  check "some qualified type application" "some(m.Result(Num, n.Err))"
    (Some_val (Type_apply (["m"], "Result", [
      Type_ref ([], "Num");
      Type_ref (["n"], "Err");
    ])));
  check "some deeply qualified type application" "some(a.b.Box(Num))"
    (Some_val (Type_apply (["a"; "b"], "Box", [Type_ref ([], "Num")])));
  check_error "applied path ends with a type" "some(m.box(Num))";
  check_error "no applied types inside types" "some(M.Box(Num))";
  check_error "type application needs arguments" "some(m.Box())";
  check "some record type" "some({ name: String, age: Int })"
    (Some_val (Type_record [
      ("name", Type_ref ([], "String"));
      ("age", Type_ref ([], "Int"));
    ]));
  check "some nested type" "some(Option({ value: Num }))"
    (Some_val (Type_apply ([], "Option", [
      Type_record [
        ("value", Type_ref ([], "Num"));
      ];
    ])));

  check "open record type" "some({ name: String, .. })"
    (Some_val (Type_open_record ([("name", Type_ref ([], "String"))], Anonymous_row)));
  check "open record type with two fields" "some({ a: Num, b: String, .. })"
    (Some_val (Type_open_record (
      [("a", Type_ref ([], "Num")); ("b", Type_ref ([], "String"))], Anonymous_row)));
  check "open record type without fields" "some({ .. })"
    (Some_val (Type_open_record ([], Anonymous_row)));
  check "named row" "some({ name: String, ..?R })"
    (Some_val (Type_open_record ([("name", Type_ref ([], "String"))], Row_var "R")));
  check "row without fields" "some({ ..?R })"
    (Some_val (Type_open_record ([], Row_var "R")));
  check "shared row" "some(({ name: String, ..?R }, String) -> { name: String, ..R })"
    (Some_val (Type_function (
      [Type_open_record ([("name", Type_ref ([], "String"))], Row_var "R");
       Type_ref ([], "String")],
      Type_open_record ([("name", Type_ref ([], "String"))], Row_ref "R"))));
  check "open record in a list" "some([{ id: Num, .. }])"
    (Some_val (Type_list (Type_open_record ([("id", Type_ref ([], "Num"))], Anonymous_row))));
  check "open record field" "some({ inner: { a: Num, .. } })"
    (Some_val (Type_record [
      ("inner", Type_open_record ([("a", Type_ref ([], "Num"))], Anonymous_row));
    ]));
  check "exact record keeps its trailing comma" "some({ a: Num, })"
    (Some_val (Type_record [("a", Type_ref ([], "Num"))]));
  check_error "row must come last" "some({ .., a: Num })";
  check_error "no comma after the row" "some({ a: Num, .., })";
  check_error "one row only" "some({ a: Num, .., .. })";
  check_error "row variable is a type name" "some({ a: Num, ..?r })";
  check_error "row needs a comma before it" "some({ a: Num .. })";
  check "label type" "some('true)" (Some_val (Type_label "true"));
  check "label union" "some('lt | 'eq | 'gt)"
    (Some_val (Type_union [Type_label "lt"; Type_label "eq"; Type_label "gt"]));
  check "union of records" "some({ ok: Num } | { err: String })"
    (Some_val (Type_union [
      Type_record [("ok", Type_ref ([], "Num"))];
      Type_record [("err", Type_ref ([], "String"))];
    ]));
  check "union of a label and a record" "some('none | { value: ?A })"
    (Some_val (Type_union [Type_label "none"; Type_record [("value", Type_var "A")]]));
  check "union with an alias" "some(Bool | 'maybe)"
    (Some_val (Type_union [Type_ref ([], "Bool"); Type_label "maybe"]));
  check "union in a list" "some(['a | 'b])"
    (Some_val (Type_list (Type_union [Type_label "a"; Type_label "b"])));
  check "union as a parameter" "some(('true | 'false) -> Num)"
    (Some_val (Type_function ([Type_union [Type_label "true"; Type_label "false"]],
      Type_ref ([], "Num"))));
  check "union after an arrow is the result" "some((String) -> { ok: Num } | { err: String })"
    (Some_val (Type_function ([Type_ref ([], "String")], Type_union [
      Type_record [("ok", Type_ref ([], "Num"))];
      Type_record [("err", Type_ref ([], "String"))];
    ])));
  check "function type as a union member" "some(((Num) -> Num) | 'none)"
    (Some_val (Type_union [
      Type_function ([Type_ref ([], "Num")], Type_ref ([], "Num"));
      Type_label "none";
    ]));
  check "function type as the last union member" "some('none | (Num) -> Num)"
    (Some_val (Type_union [
      Type_label "none";
      Type_function ([Type_ref ([], "Num")], Type_ref ([], "Num"));
    ]));
  check "nested union is flattened" "some('a | ('b | 'c))"
    (Some_val (Type_union [Type_label "a"; Type_label "b"; Type_label "c"]));
  check "nested union first is flattened" "some(('a | 'b) | 'c)"
    (Some_val (Type_union [Type_label "a"; Type_label "b"; Type_label "c"]));
  check "deeply nested union is flattened" "some((('a | ('b))) | ('c | 'd))"
    (Some_val (Type_union [Type_label "a"; Type_label "b"; Type_label "c"; Type_label "d"]));
  check "grouped union alone is the union" "some(('a | 'b))"
    (Some_val (Type_union [Type_label "a"; Type_label "b"]));
  check "union inside a parameter is not flattened outward" "some(('a | 'b) -> 'c | 'd)"
    (Some_val (Type_function ([Type_union [Type_label "a"; Type_label "b"]],
      Type_union [Type_label "c"; Type_label "d"])));
  check "repeated members are kept for the checker" "some('a | 'a)"
    (Some_val (Type_union [Type_label "a"; Type_label "a"]));
  check "union in a record field" "some({ result: 'ok | 'failed })"
    (Some_val (Type_record [("result", Type_union [Type_label "ok"; Type_label "failed"])]));
  check "union as a type argument" "some(Box('a | 'b, Num))"
    (Some_val (Type_apply ([], "Box", [Type_union [Type_label "a"; Type_label "b"]; Type_ref ([], "Num")])));
  check "type entries with unions" "{ Bool: 'true | 'false, OrderingResult = 'lt | 'eq | 'gt }"
    (Record [
      Type_field ("Bool", [], Type_union [Type_label "true"; Type_label "false"]);
      Type_local ("OrderingResult", [], Type_union [Type_label "lt"; Type_label "eq"; Type_label "gt"]);
    ]);
  check_error "union needs a member after |" "some('a |)";
  check_error "union needs a member before |" "some(| 'a)";
  check_error "no double bar" "some('a || 'b)";
  check_error "label type is not an expression type name" "some('A)";
  check "list type" "some([Num])" (Some_val (Type_list (Type_ref ([], "Num"))));
  check "nested list type" "some([[?A]])" (Some_val (Type_list (Type_list (Type_var "A"))));
  check "list of records" "some([{ name: String }])"
    (Some_val (Type_list (Type_record [("name", Type_ref ([], "String"))])));
  check "function type" "some((Num) -> String)"
    (Some_val (Type_function ([Type_ref ([], "Num")], Type_ref ([], "String"))));
  check "function type with two parameters" "some((?A, A) -> A)"
    (Some_val (Type_function ([Type_var "A"; Type_ref ([], "A")], Type_ref ([], "A"))));
  check "function type with trailing comma" "some((Num,) -> Num)"
    (Some_val (Type_function ([Type_ref ([], "Num")], Type_ref ([], "Num"))));
  check "function type without parameters" "some(() -> Num)"
    (Some_val (Type_function ([], Type_ref ([], "Num"))));
  check "arrow is right-associative in types" "some((Num) -> (Num) -> Num)"
    (Some_val (Type_function ([Type_ref ([], "Num")],
      Type_function ([Type_ref ([], "Num")], Type_ref ([], "Num")))));
  check "function returning a list" "some((Num) -> [Num])"
    (Some_val (Type_function ([Type_ref ([], "Num")], Type_list (Type_ref ([], "Num")))));
  check "list of functions" "some([(Num) -> Num])"
    (Some_val (Type_list (Type_function ([Type_ref ([], "Num")], Type_ref ([], "Num")))));
  check "function taking a function" "some(((Num) -> Num, [Num]) -> [Num])"
    (Some_val (Type_function (
      [Type_function ([Type_ref ([], "Num")], Type_ref ([], "Num"));
       Type_list (Type_ref ([], "Num"))],
      Type_list (Type_ref ([], "Num")))));
  check "function type in a record" "some({ compare: (A, A) -> Ordering })"
    (Some_val (Type_record [
      ("compare", Type_function ([Type_ref ([], "A"); Type_ref ([], "A")], Type_ref ([], "Ordering")));
    ]));
  check "function type as a type argument" "some(Box((Num) -> Num))"
    (Some_val (Type_apply ([], "Box", [Type_function ([Type_ref ([], "Num")], Type_ref ([], "Num"))])));
  check "grouping in types" "some((Num))" (Some_val (Type_ref ([], "Num")));
  check "grouped function type as a result" "some((Num) -> ((Num) -> Num))"
    (Some_val (Type_function ([Type_ref ([], "Num")],
      Type_function ([Type_ref ([], "Num")], Type_ref ([], "Num")))));
  check_file_error "no tuple types" "x = some((Num, String))"
    "The parenthesised types at :1:10 are not followed by '->': Duetto has no tuple types";
  check_file_error "no one-element tuple types" "x = some((Num,))"
    "The parenthesised types at :1:10 are not followed by '->': Duetto has no tuple types";
  check_error "empty parentheses need an arrow" "some(())";
  check_error "list type needs one element type" "some([Num, Num])";
  check_error "list type is not empty" "some([])";
  check_error "arrow needs a parameter list" "some(Num -> Num)";
  check_error "arrow needs a result" "some((Num) ->)";
  check "some type variable" "some(?A)" (Some_val (Type_var "A"));
  check "some multi-letter type variable" "some(?Key)" (Some_val (Type_var "Key"));
  check "type variable then bare use" "some({ first: ?A, second: A })"
    (Some_val (Type_record [
      ("first", Type_var "A");
      ("second", Type_ref ([], "A"));
    ]));
  check "type variable as an argument" "some(Result(?A, String))"
    (Some_val (Type_apply ([], "Result", [Type_var "A"; Type_ref ([], "String")])));
  check_error "type variable needs a type name" "some(?a)";
  check_error "no space after ?" "some(? A)";
  check_error "type variable is not an expression" "?A";

  check "empty struct" "{}" (Record []);
  check "punned name entry" "{ x }"
    (Record [
      Field ("x", Ident "x");
    ]);
  check "punned path entry" "{ person.name }"
    (Record [
      Field ("name", Proj (Ident "person", "name"));
    ]);
  check "punned type entry" "{ Bool }"
    (Record [
      Type_field ("Bool", [], Type_ref ([], "Bool"));
    ]);
  check "punned qualified type entry" "{ m.Bool }"
    (Record [
      Type_field ("Bool", [], Type_ref (["m"], "Bool"));
    ]);
  check "punned deeply qualified type entry" "{ a.b.Bool }"
    (Record [
      Type_field ("Bool", [], Type_ref (["a"; "b"], "Bool"));
    ]);
  check "punned deep value path" "{ a.b.c }"
    (Record [
      Field ("c", Proj (Proj (Ident "a", "b"), "c"));
    ]);
  check_error "punned path cannot go from type to value" "{ Mod.value }";
  check_error "punned path cannot go back to values" "{ pkg.Type.value }";
  check_error "no types inside types in punned paths" "{ Mod.Type }";
  check_error "no types inside types after a value path" "{ pkg.Type.Ctor }";

  check "public type entry" "{ Num2: Num }"
    (Record [Type_field ("Num2", [], Type_ref ([], "Num"))]);
  check "private type entry" "{ Pair = { first: Num, second: Num } }"
    (Record [
      Type_local ("Pair", [], Type_record [
        ("first", Type_ref ([], "Num"));
        ("second", Type_ref ([], "Num"));
      ]);
    ]);
  check "type constructor entry" "{ Box(A): { value: A } }"
    (Record [
      Type_field ("Box", ["A"], Type_record [("value", Type_ref ([], "A"))]);
    ]);
  check "type constructor with many params" "{ Pair(A, B,) = { a: A, b: B } }"
    (Record [
      Type_local ("Pair", ["A"; "B"], Type_record [
        ("a", Type_ref ([], "A"));
        ("b", Type_ref ([], "B"));
      ]);
    ]);
  check "type entry referring to a qualified type" "{ Flag: m.Bool }"
    (Record [Type_field ("Flag", [], Type_ref (["m"], "Bool"))]);
  check "type entry applying a qualified constructor" "{ NumOrd = m.Ordering(Num) }"
    (Record [
      Type_local ("NumOrd", [], Type_apply (["m"], "Ordering", [Type_ref ([], "Num")]));
    ]);
  check "types among values" "{ T: Num, x: some(T) }"
    (Record [
      Type_field ("T", [], Type_ref ([], "Num"));
      Field ("x", Some_val (Type_ref ([], "T")));
    ]);
  check "private types in a block" "{ T = Num, x = some(T), <<x }"
    (Block ([
      Type_local ("T", [], Type_ref ([], "Num"));
      Local ("x", Some_val (Type_ref ([], "T")))], Ident "x"));
  check_error "type entry needs a type" "{ T: 1 }";
  check_error "type params are type names" "{ Box(a): { value: a } }";
  check_error "type params are not empty" "{ Box(): Num }";
  check_error "value entry has no params" "{ f(x): 1 }";
  check_file "type entries at file level" "Bool2: Num,\nBox(A) = { value: A },\nx: 1"
    (Record [
      Type_field ("Bool2", [], Type_ref ([], "Num"));
      Type_local ("Box", ["A"], Type_record [("value", Type_ref ([], "A"))]);
      Field ("x", Num "1");
    ]);
  check "simple struct" "{ answer: 42 }"
    (Record [
      Field ("answer", Num "42");
    ]);
  check "nested struct" "{ answer: 42, config: { retries: 3 } }"
    (Record [
      Field ("answer", Num "42");
      Field ("config", Record [
        Field ("retries", Num "3");
      ]);
    ]);
  check "struct with identifier field" "{ answer: x }"
    (Record [
      Field ("answer", Ident "x");
    ]);
  check "struct with projection field" "{ name: person.name }"
    (Record [
      Field ("name", Proj (Ident "person", "name"));
    ]);
  check "local entry" "{ answer = 42 }"
    (Record [
      Local ("answer", Num "42");
    ]);
  check "do entry" "{ do answer() }"
    (Record [
      Do (Call (Ident "answer", []));
    ]);
  check "result entry" "{ <<answer }"
    (Block ([], Ident "answer"));
  check "locals and result" "{ x = 1, y = x, <<y }"
    (Block ([
      Local ("x", Num "1");
      Local ("y", Ident "x")], Ident "y"));
  check "trailing comma" "{ answer: 42, }"
    (Record [
      Field ("answer", Num "42");
    ]);
  check "trailing comma after result" "{ x = 1, <<x, }"
    (Block ([
      Local ("x", Num "1")], Ident "x"));

  check "ensure" "{ ensure x == 1 }"
    (Record [Ensure (Eq (Ident "x", Num "1"))]);
  check "ensure among entries" "{ x = f(1), ensure x == 2, ensure g(x), <<x }"
    (Block ([
      Local ("x", Call (Ident "f", [Num "1"]));
      Ensure (Eq (Ident "x", Num "2"));
      Ensure (Call (Ident "g", [Ident "x"]))], Ident "x"));
  check "ensure trailing comma" "{ ensure a == b, }"
    (Record [Ensure (Eq (Ident "a", Ident "b"))]);
  check "ensure with lambda and calls" "{ ensure map(xs, x -> x + 1) == [2, 3] }"
    (Record [
      Ensure (Eq (
        Call (Ident "map", [Ident "xs"; Lambda (["x"], Add (Ident "x", Num "1"))]),
        List [Num "2"; Num "3"]));
    ]);
  check "ensure on a struct" "{ ensure f(x) == { ok: 1 } }"
    (Record [
      Ensure (Eq (Call (Ident "f", [Ident "x"]), Record [Field ("ok", Num "1")]));
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
