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
    let ast = Duetto.Parser.main Duetto.Lexer.token lexbuf in
    let result = eval ast in
    Printf.printf "Result: %d\n" result
  with 
  | Duetto.Lexer.Error error -> 
      Printf.eprintf "Lexical error: %s\n" (Duetto.Lexer.string_of_error error);
      exit 1      
