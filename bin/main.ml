module A = Duetto.Ast.Located
module StrMap = Map.Make(String)

let eval_num literal =
  match int_of_string_opt literal with
  | Some n -> n
  | None ->
      failwith (Printf.sprintf
        "Runtime numeric error: expected an integer literal, got %S" literal)


type parsed_expr =
  | Atom of int
  | Label of string
  | Tree of (string * parsed_expr) list
[@@deriving show]

let rec atom_eq a1 a2 = match (a1, a2) with
  | (Atom n, Atom m) -> n = m
  | (Label l, Label m) -> l = m
  | (Tree fields1, Tree fields2) ->
    let map1 = fields1 |> List.to_seq |> StrMap.of_seq in
    let map2 = fields2 |> List.to_seq |> StrMap.of_seq in
    StrMap.equal atom_eq map1 map2
  | _ -> false

let rec eval (expr : A.expr) =
  match expr.node with
  | A.Num literal -> Atom (eval_num literal)
  | A.String _ ->
      failwith "Runtime evaluator does not support string values yet"
  | A.Ident name ->
      failwith (Printf.sprintf
        "Runtime evaluator does not support identifiers yet (%s)" name)
  | A.Proj (_, field) ->
      failwith (Printf.sprintf
        "Runtime evaluator does not support projection yet (. %s)" field)
  | A.Call _ ->
      failwith "Runtime evaluator does not support function calls yet"
  | A.Lambda _ ->
      failwith "Runtime evaluator does not support lambdas yet"
  | A.Some_val typ ->
    let rec summon_value (typ_desc : A.type_expr) = match typ_desc.node with
      | A.Type_ident "Num" -> Atom (Random.int 100)
      | A.Type_ident _ -> failwith "Only numbers can be summoned"
      | A.Type_apply _ -> failwith "Type application is not supported yet"
      | A.Type_record fields ->
        Tree (fields
        |> List.map (fun (name, typ_dsc) -> (name, summon_value typ_dsc)))
    in summon_value typ
  | A.Struct fields -> Tree (List.filter_map eval_field fields)
  | A.List entries ->
    Tree (entries |> List.mapi (fun idx item -> (string_of_int idx, eval item)))
  | A.Concat (_, _) ->
      failwith "Runtime evaluator does not support ++ yet"
  | A.Eq (lhs, rhs) -> Label (if atom_eq (eval lhs) (eval rhs) then "true" else "false")
  | A.Label l -> Label l
  | A.Case (scrutinee, branches) ->
      let value = eval scrutinee in
      let has_fields fields =
        match value with
        | Tree entries -> List.for_all (fun f -> List.mem_assoc f entries) fields
        | _ -> false
      in
      let matches (pattern : A.pattern) =
        match pattern.node, value with
        | A.Label_pattern l, Label m -> l = m
        | A.Record_pattern fields, Tree entries ->
            has_fields fields && List.length fields = List.length entries
        | A.Open_record_pattern fields, Tree _ -> has_fields fields
        | _ -> false
      in
      (* Record patterns bind their fields, which this evaluator cannot use
         yet, since it has no identifiers. *)
      (match List.find_opt (fun (b : A.case_branch) -> matches b.pattern) branches with
      | Some branch -> eval branch.body
      | None -> failwith "case: no branch matches the value")
  | A.Add (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (a + b)
      | _ -> failwith "can only add atoms")
  | A.Sub (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (a - b)
      | _ -> failwith "can only subtract atoms")
  | A.Mul (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (a * b)
      | _ -> failwith "can only multiply atoms")
  | A.Div (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (a / b)
      | _ -> failwith "can only divide atoms")

and eval_field (entry : A.struct_entry) =
  match entry.node with
  | A.Field (s, e) -> Some (s, eval e)
  | A.Local (s, e) -> Some (s, eval e)
  | A.Ensure e ->
      let pos = entry.loc.start_pos in
      (match eval e with
      | Label "true" -> None
      | Label "false" ->
          failwith (Printf.sprintf "ensure failed at %d:%d" pos.line pos.column)
      | _ ->
          failwith (Printf.sprintf
            "ensure at %d:%d needs a true or false condition" pos.line pos.column))
  | A.Spec (title, body) ->
      (* Run the spec now: its locals and ensures, in order. A spec adds no
         field to the struct. *)
      (try List.iter (fun entry -> ignore (eval_field entry)) body
       with Failure message ->
         failwith (Printf.sprintf "spec '%s': %s" title message));
      None
  | A.Result _ ->
      failwith "Results are not supported"

let () =
  Random.self_init ();
  print_endline "Duetto";

  try
    let lexbuf = Lexing.from_channel stdin in
    lexbuf.lex_curr_p <- {
      lexbuf.lex_curr_p with
      pos_fname = "<stdin>";
    };

    let ast = Duetto.Parse.parse lexbuf in
    let result = eval ast in
    let ast_text =
      Format.asprintf "%a" A.pp_expr ast
    in
    Printf.printf "AST: %s\n" ast_text;
    Printf.printf "Result: %s\n" (show_parsed_expr result)
  with
  | Duetto.Diagnostic.Error error ->
      Printf.eprintf "Lexical error: %s\n" (Duetto.Diagnostic.string_of_error error);
      exit 1
  | Failure message ->
      Printf.eprintf "%s\n" message;
      exit 1
