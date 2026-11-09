{
open Parser
}

let digit = ['0'-'9']
let whitespace = [' ' '\t' '\r']+

rule token = parse
  | whitespace { token lexbuf }
  | '\n' {
      Lexing.new_line lexbuf;
      token lexbuf
    }
    
  | digit+ {
      INT (int_of_string (Lexing.lexeme lexbuf))
    }

  | '+' { PLUS }
  | '-' { MINUS }
  | '*' { TIMES }
  | '/' { DIV }
  | '(' { LPAREN }
  | ')' { RPAREN }

  | eof { EOF }

  | _ { 
    let pos = Lexing.lexeme_start_p lexbuf in
    let column = pos.pos_cnum - pos.pos_bol + 1 in
    let character = Lexing.lexeme lexbuf in
    raise (Diagnostic.Error(
      Diagnostic.Unexpected_character {
        character;
        position = {
          filename = pos.pos_fname;
          line = pos.pos_lnum;
          column;
        };
      }
    ) 
    )
  }
