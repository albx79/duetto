module A = Duetto.Ast.Located

let eval_num literal =
  match int_of_string_opt literal with
  | Some n -> n
  | None ->
      failwith (Printf.sprintf
        "Runtime numeric error: expected an integer literal, got %S" literal)

type parsed_expr =
  | Atom of int
  | Tree of (string * parsed_expr) list
[@@deriving show]

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
  | A.Some_val { node = A.Type_ident "Num"; _ } ->
      Atom (Random.int 100)
  | A.Some_val _ ->
      failwith "Runtime evaluator does not support some(...) yet"
  | A.Struct fields -> Tree (List.map eval_field fields)
  | A.List _ ->
      failwith "Runtime evaluator does not support list values yet"
  | A.Concat (_, _) ->
      failwith "Runtime evaluator does not support ++ yet"
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
  | A.Field (s, e) -> (s, eval e)
  | A.Local (s, e) -> (s, eval e)
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
