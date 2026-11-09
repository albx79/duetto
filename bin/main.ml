let rec eval = function
  | Duetto.Ast.Int n -> n
  | Duetto.Ast.Add (a, b) -> eval a + eval b
  | Duetto.Ast.Sub (a, b) -> eval a - eval b
  | Duetto.Ast.Mul (a, b) -> eval a * eval b
  | Duetto.Ast.Div (a, b) -> eval a / eval b

let () =
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
