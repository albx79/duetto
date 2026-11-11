{
open Parser

let position_of (pos : Lexing.position) : Diagnostic.position = {
  filename = pos.pos_fname;
  line = pos.pos_lnum;
  column = pos.pos_cnum - pos.pos_bol + 1;
}

let error e = raise (Diagnostic.Error e)

let keyword_or_ident = function
  | "case" -> CASE
  | "some" -> SOME
  | "ensure" -> ENSURE
  | name -> LIDENT name

(* Advance the line counter past every newline in [text], which was just
   matched in one lexeme. [Lexing.new_line] only handles a lexeme that ends
   with the newline. *)
let skip_newlines lexbuf text =
  let start = Lexing.lexeme_start_p lexbuf in
  String.iteri (fun i c ->
    if c = '\n' then
      lexbuf.Lexing.lex_curr_p <- {
        lexbuf.Lexing.lex_curr_p with
        pos_lnum = lexbuf.Lexing.lex_curr_p.pos_lnum + 1;
        pos_bol = start.pos_cnum + i + 1;
      })
    text
}

let digit = ['0'-'9']
let exponent = ['e' 'E'] ['+' '-']? digit+
let number = digit+ exponent?
let lident_start = ['a'-'z' '_']
let lident_char = ['a'-'z' '0'-'9' '_']
let uident_start = ['A'-'Z']
let uident_char = ['a'-'z' 'A'-'Z' '0'-'9']
let ident_char = ['a'-'z' 'A'-'Z' '0'-'9' '_']
let whitespace = [' ' '\t' '\r']+

rule token = parse
  | whitespace { token lexbuf }
  | '\n' {
      Lexing.new_line lexbuf;
      token lexbuf
    }
  | "#!" | "#[" | "]#" | "#_" as token{
        error (Diagnostic.Reserved_token {
          token;
          position = position_of (Lexing.lexeme_start_p lexbuf);
        })
      }
  | "#" [^ '\n']* { token lexbuf }

  (* A spec title is free text up to the opening brace (spec, section 3.6). *)
  | "spec" ([' ' '\t' '\r' '\n'] [^ '{']* as title) {
      skip_newlines lexbuf title;
      SPEC (String.trim title)
    }
  | "spec" { SPEC "" }

  | number as n { NUM n }
  | '"' {
      let start = Lexing.lexeme_start_p lexbuf in
      let s = string (Buffer.create 16) start lexbuf in
      lexbuf.lex_start_p <- start;
      STRING s
    }
  | '\'' (lident_start lident_char* as l) { LABEL l }
  | lident_start lident_char* as name { keyword_or_ident name }
  | uident_start uident_char* '_' ident_char* {
      let lexeme = Lexing.lexeme lexbuf in
      let underscore_index = String.index lexeme '_' in
      let start = Lexing.lexeme_start_p lexbuf in
      let underscore_pos = {
        start with
        pos_cnum = start.pos_cnum + underscore_index;
      } in
      error (Diagnostic.Unexpected_character {
        character = "_";
        position = position_of underscore_pos;
      })
    }
  | uident_start uident_char* as name { UIDENT name }

  | "->" { ARROW }
  | "==" { EQEQ }
  | "<<" { RESULT }
  | ".." { DOTDOT }
  | "++" { CONCAT }
  | '+' { PLUS }
  | '-' { MINUS }
  | '*' { TIMES }
  | '/' { DIV }
  | '%' { MOD }
  | '=' { EQUAL }
  | ':' { COLON }
  | ',' { COMMA }
  | '.' { DOT }
  | '|' { BAR }
  | '?' { QUESTION }
  | '(' { LPAREN }
  | ')' { RPAREN }
  | '{' { LBRACE }
  | '}' { RBRACE }
  | '[' { LBRACKET }
  | ']' { RBRACKET }

  | eof { EOF }

  | _ as character {
      error (Diagnostic.Unexpected_character {
        character = String.make 1 character;
        position = position_of (Lexing.lexeme_start_p lexbuf);
      })
    }

and string buf start = parse
  | '"' { Buffer.contents buf }
  | "\\\"" { Buffer.add_char buf '"'; string buf start lexbuf }
  | "\\\\" { Buffer.add_char buf '\\'; string buf start lexbuf }
  | "\\n" { Buffer.add_char buf '\n'; string buf start lexbuf }
  | "\\t" { Buffer.add_char buf '\t'; string buf start lexbuf }
  | '\\' (_ as c) {
      error (Diagnostic.Invalid_escape {
        sequence = Printf.sprintf "\\%c" c;
        position = position_of (Lexing.lexeme_start_p lexbuf);
      })
    }
  | '\n' | eof {
      error (Diagnostic.Unterminated_string { position = position_of start })
    }
  | [^ '"' '\\' '\n']+ as s { Buffer.add_string buf s; string buf start lexbuf }
