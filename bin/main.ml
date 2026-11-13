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

let rec eval = function
  | Duetto.Ast.Num literal -> Atom (eval_num literal)
  | Duetto.Ast.Ident name ->
      failwith (Printf.sprintf
        "Runtime evaluator does not support identifiers yet (%s)" name)
  | Duetto.Ast.Proj (_, field) ->
      failwith (Printf.sprintf
        "Runtime evaluator does not support projection yet (. %s)" field)
  | Duetto.Ast.Some_val (Duetto.Ast.Type_ident "Num") -> Atom (Random.int 100)
  | Duetto.Ast.Some_val _ ->
      failwith "Runtime evaluator does not support some(...) yet"
  | Duetto.Ast.Struct fields -> Tree (List.map eval_field fields)
  | Duetto.Ast.Add (a, b) -> 
    (match (eval a, eval b) with
    | (Atom a, Atom b) -> Atom (a + b)
    | _ -> failwith "can only add atoms")
  | Duetto.Ast.Sub (a, b) -> 
    (match (eval a, eval b) with
    | (Atom a, Atom b) -> Atom (a - b)
    | _ -> failwith "can only subtract atoms")
  | Duetto.Ast.Mul (a, b) -> 
    (match (eval a, eval b) with
    | (Atom a, Atom b) -> Atom (a * b)
    | _ -> failwith "can only multiply atoms")
  | Duetto.Ast.Div (a, b) -> 
    (match (eval a, eval b) with
    | (Atom a, Atom b) -> Atom (a / b)
    | _ -> failwith "can only divide atoms")
  and eval_field = function
      | Field (s, e) -> (s, eval e)
      | Local (s, e) -> (s, eval e)
      | Result e -> 
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
    Printf.printf "AST: %s\n" (Duetto.Ast.show_expr ast);
    Printf.printf "Result: %s\n" (show_parsed_expr result)
  with 
  | Duetto.Diagnostic.Error error -> 
      Printf.eprintf "Lexical error: %s\n" (Duetto.Diagnostic.string_of_error error);
      exit 1
  | Failure message ->
      Printf.eprintf "%s\n" message;
      exit 1
