{
open Parser
}

let digit = ['0'-'9']
let whitespace = [' ' '\t' '\r' '\n']+

rule token = parse
  | whitespace { token lexbuf }

  | digit+ {
      INT (int_of_string (Lexing.lexeme lexbuf))
    }

  | '+' { PLUS }
  | '*' { TIMES }
  | '(' { LPAREN }
  | ')' { RPAREN }

  | eof { EOF }

  | _ { failwith "Unexpected character" }
