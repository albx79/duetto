module S = Duetto.Scheme
open S

let failures = ref 0

let fail name fmt =
  incr failures;
  Printf.printf ("FAIL %s\n" ^^ fmt ^^ "\n") name

(* A printed signature must also be valid Duetto type syntax (spec, section
   12.5): it must parse as the body of a public type entry. *)
let check_parses name printed =
  let src = "T: " ^ printed in
  match Duetto.Parse.parse_unit (Lexing.from_string src) with
  | _ -> ()
  | exception Duetto.Diagnostic.Error e ->
      fail name "  printed %s, which does not parse: %s" printed
        (Duetto.Diagnostic.string_of_error e)

let check name ty expected =
  let actual = to_string (of_ty ty) in
  if actual <> expected then
    fail name "  expected: %s\n  actual:   %s" expected actual
  else check_parses name actual

let check_lacks name ty expected =
  let actual = (of_ty ty).lacks in
  if actual <> expected then
    let show l =
      String.concat "; "
        (List.map (fun (r, fs) -> Printf.sprintf "%d lacks %s" r (String.concat "," fs)) l)
    in
    fail name "  expected: %s\n  actual:   %s" (show expected) (show actual)

let unit = Record ([], Closed)
let fn params result = Function (params, result)

let () =
  check "Num" Num "Num";
  check "String" String "String";
  check "Never" Never "Never";
  check "an empty label set is Never" (Labels []) "Never";
  check "one label" (Labels ["a"]) "'a";
  check "labels keep their order" (Labels ["lt"; "eq"; "gt"]) "'lt | 'eq | 'gt";
  check "list" (List Num) "[Num]";
  check "list of labels" (List (Labels ["a"; "b"])) "['a | 'b]";

  check "empty record" unit "{}";
  check "exact record" (Record (["theme", String; "size", Num], Closed))
    "{ theme: String, size: Num }";

  (* Formal core, case A1 and A9: a function from {} has no arguments. *)
  check "zero arguments" (fn [unit] Num) "() -> Num";
  check "empty list result" (fn [unit] (List Never)) "() -> [Never]";
  check "two arguments" (fn [Num; Num] (Labels ["true"; "false"]))
    "(Num, Num) -> 'true | 'false";
  check "label parameter" (fn [Labels ["true"; "false"]] Num) "('true | 'false) -> Num";
  check "function result" (fn [Num] (fn [Num] Num)) "(Num) -> (Num) -> Num";
  check "function parameter" (fn [fn [Num] Num] Num) "((Num) -> Num) -> Num";
  check "list of functions" (List (fn [Num] Num)) "[(Num) -> Num]";
  check "record of functions"
    (Record (["compare", fn [Num; Num] (Labels ["eq"; "lt"])], Closed))
    "{ compare: (Num, Num) -> 'eq | 'lt }";

  (* Formal core, cases A4 and A7. *)
  check "identity" (fn [Var 0] (Var 0)) "(?X) -> X";
  check "pick" (fn [Var 0; Var 1] (Var 0)) "(?X, ?Y) -> X";
  check "names follow first occurrence, not numbering" (fn [Var 7; Var 3] (Var 3))
    "(?X, ?Y) -> Y";
  check "names after Z"
    (fn [Var 0; Var 1; Var 2; Var 3; Var 4] (Var 4))
    "(?X, ?Y, ?Z, ?X1, ?X2) -> X2";
  check "variable in a list" (fn [List (Var 0)] Num) "([?X]) -> Num";

  (* Formal core, case A3: a row that occurs once is anonymous. *)
  check "open record parameter"
    (fn [Record (["name", String], Row_var 0)] String)
    "({ name: String, .. }) -> String";
  check "open record with no fields" (fn [Record ([], Row_var 0)] Num) "({ .. }) -> Num";
  (* Formal core, case R12: a row that occurs twice is named. *)
  check "shared row"
    (fn [Record (["a", Num], Row_var 0)] (Record ([], Row_var 0)))
    "({ a: Num, ..?R }) -> { ..R }";
  check "named and anonymous rows"
    (fn [Record ([], Row_var 5); Record ([], Row_var 1)] (Record (["b", Var 0], Row_var 5)))
    "({ ..?R }, { .. }) -> { b: ?X, ..R }";

  check_lacks "a closed type has no rows" (fn [Num] Num) [];
  check_lacks "a row lacks the fields next to it"
    (fn [Record (["name", String], Row_var 0)] String)
    [ (0, ["name"]) ];
  check_lacks "a row lacks the fields next to every occurrence"
    (fn [Record (["a", Num], Row_var 0); Record (["b", Num; "a", Num], Row_var 0)]
       (Record ([], Row_var 1)))
    [ (0, ["a"; "b"]); (1, []) ];

  if !failures > 0 then exit 1 else print_endline "scheme tests passed"
