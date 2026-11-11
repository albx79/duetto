let eval_num literal =
  match int_of_string_opt literal with
  | Some n -> n
  | None ->
      failwith (Printf.sprintf
        "Runtime numeric error: expected an integer literal, got %S" literal)

let rec eval = function
  | Duetto.Ast.Num literal -> eval_num literal
  | Duetto.Ast.Ident name ->
      failwith (Printf.sprintf
        "Runtime evaluator does not support identifiers yet (%s)" name)
  | Duetto.Ast.Proj (_, field) ->
      failwith (Printf.sprintf
        "Runtime evaluator does not support projection yet (. %s)" field)
  | Duetto.Ast.Some (Duetto.Ast.Type_ident "Num") -> Random.int 100
  | Duetto.Ast.Some _ ->
      failwith "Runtime evaluator does not support some(...) yet"
  | Duetto.Ast.Struct _ ->
      failwith "Runtime evaluator does not support struct values yet"
  | Duetto.Ast.Add (a, b) -> eval a + eval b
  | Duetto.Ast.Sub (a, b) -> eval a - eval b
  | Duetto.Ast.Mul (a, b) -> eval a * eval b
  | Duetto.Ast.Div (a, b) -> eval a / eval b

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
    Printf.printf "AST: %s\n" (Duetto.Ast.show_expr ast);
    Printf.printf "Result: %d\n" result
  with 
  | Duetto.Diagnostic.Error error -> 
      Printf.eprintf "Lexical error: %s\n" (Duetto.Diagnostic.string_of_error error);
      exit 1
  | Failure message ->
      Printf.eprintf "%s\n" message;
      exit 1
