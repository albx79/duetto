{
open Parser

type error = {
  character: string;
  line: int;
  column: int;
}

exception Error of error

let string_of_error error =
  Printf.sprintf
    "Unexpected character '%s' at %d:%d"
    error.character
    error.line
    error.column

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
    raise (Error {
        character;
        line = pos.pos_lnum;
        column;
      }
    )
  }
