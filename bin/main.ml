module A = Duetto.Ast.Located
module StrMap = Map.Make(String)
module Num = Duetto.Num

let eval_num literal =
  match Num.of_string_opt literal with
  | Some n -> n
  | None ->
      failwith (Printf.sprintf
        "Runtime numeric error: invalid number `%S`" literal)


type parsed_expr =
  | Atom of Num.t
  | Label of string
  | Tree of (string * parsed_expr) list
[@@deriving show]

let rec atom_eq a1 a2 = match (a1, a2) with
  | (Atom n, Atom m) -> Num.equal n m
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
  | A.Every _ -> failwith "every is not supported yet"
  | A.Some_val typ ->
    let rec summon_value (typ_desc : A.type_expr) = match typ_desc.node with
      | A.Type_ref ([], "Num") -> Atom (Num.of_ints (Random.int 100) (Random.int 100))
      | A.Type_ref _ -> failwith "Only numbers can be summoned"
      | A.Type_apply _ -> failwith "Type application is not supported yet"
      | A.Type_list _ -> failwith "Lists cannot be summoned yet"
      | A.Type_open_record _ -> failwith "Open records cannot be summoned yet"
      | A.Type_label l -> Label l
      | A.Type_union _ -> failwith "Unions cannot be summoned yet"
      | A.Type_function _ -> failwith "Functions cannot be summoned yet"
      | A.Type_var name ->
          failwith (Printf.sprintf "Type variables cannot be summoned yet (?%s)" name)
      | A.Type_record fields ->
        Tree (fields
        |> List.map (fun (name, typ_dsc) -> (name, summon_value typ_dsc)))
    in summon_value typ
  | A.Record fields -> Tree (List.filter_map eval_field fields)
  | A.Block _ -> failwith "Blocks are not supported"
  | A.List entries ->
    Tree (entries |> List.mapi (fun idx item -> (string_of_int idx, eval item)))
  | A.Concat (_, _) ->
      failwith "Runtime evaluator does not support ++ yet"
  | A.Eq (lhs, rhs) -> Label (if atom_eq (eval lhs) (eval rhs) then "true" else "false")
  | A.Label l -> Label l
  | A.Double _ -> failwith "Doubles are not supported yet"
  | A.Compare _ -> failwith "Comparisons under an ordering are not supported yet"
  | A.Case (scrutinee, branches) ->
      let value = eval scrutinee in
      (* Binders match but bind nothing, since this evaluator has no
         identifiers yet. *)
      let rec matches (pattern : A.pattern) value =
        match pattern.node, value with
        | A.Label_pattern l, Label m -> l = m
        | A.Num_pattern n, Atom m -> eval_num n = m
        | A.Binder _, _ | A.Some_pattern _, _ -> true
        | A.Pinned _, _ -> failwith "Pinned patterns are not supported yet"
        | A.Record_pattern fields, Tree entries ->
            List.length fields = List.length entries && fields_match fields entries
        | A.Open_record_pattern fields, Tree entries -> fields_match fields entries
        | _ -> false
      and fields_match fields entries =
        List.for_all (fun (name, p) ->
          match List.assoc_opt name entries with
          | Some v -> matches p v
          | None -> false)
          fields
      in
      (match List.find_opt (fun (b : A.case_branch) -> matches b.pattern value) branches with
      | Some branch -> eval branch.body
      | None -> failwith "case: no branch matches the value")
  | A.Neg e ->
      (match eval e with
      | Atom n -> Atom (Num.neg n)
      | _ -> failwith "can only negate atoms")
  | A.Add (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (Num.add a b)
      | _ -> failwith "can only add atoms")
  | A.Sub (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (Num.sub a b)
      | _ -> failwith "can only subtract atoms")
  | A.Mul (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (Num.mul a b)
      | _ -> failwith "can only multiply atoms")
  | A.Div (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (Num.div a b)
      | _ -> failwith "can only divide atoms")
  | A.Mod (a, b) ->
      (match (eval a, eval b) with
      | (Atom a, Atom b) -> Atom (Num.rem a b)
      | _ -> failwith "can only mod atoms")

and eval_field (entry : A.struct_entry) =
  match entry.node with
  | A.Field (s, e) -> Some (s, eval e)
  (* Locals aren't needed because we don't resolve names yet *)
  | A.Local (s, e) -> None
  (* Types exist only at compile time (spec, section 3.8). *)
  | A.Type_field _ | A.Type_local _ -> None
  | A.Ensure e ->
      let pos = Duetto.Position.to_string entry.loc.start_pos in
      (match eval e with
      | Label "true" -> None
      | Label "false" ->
          failwith (Printf.sprintf "ensure failed at %s" pos)
      | _ ->
          failwith (Printf.sprintf
            "ensure at %s needs a true or false condition" pos))
  | A.Do _ ->
      failwith "Do entries are not supported"
  | A.Spec (segments, body) ->
      let title =
        String.concat "" (List.map (fun (s : A.title_segment) ->
          match s.node with
          | A.Title_text t -> t
          | A.Title_mark (path, name) -> "`" ^ String.concat "." (path @ [name]) ^ "`")
          segments)
      in
      (* Run the spec now: its locals and ensures, in order. A spec adds no
         field to the struct. *)
      (try List.iter (fun entry -> ignore (eval_field entry)) body
       with Failure message ->
         failwith (Printf.sprintf "spec '%s': %s" title message));
      None

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
      Printf.eprintf "Error: %s\n" (Duetto.Diagnostic.string_of_error error);
      exit 1
  | Failure message ->
      Printf.eprintf "%s\n" message;
      exit 1
