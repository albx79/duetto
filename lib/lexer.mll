{
open Tokens

let position_of (pos : Lexing.position) : Diagnostic.position = {
  filename = pos.pos_fname;
  line = pos.pos_lnum;
  column = pos.pos_cnum - pos.pos_bol + 1;
}

let error e = raise (Diagnostic.Error e)

(* How a token is shown in an error message, as it would be written in the
   source; None for the end of input. *)
let describe = function
  | NUM n -> Some n
  | STRING s -> Some (Printf.sprintf "%S" s)
  | LABEL l -> Some ("'" ^ l)
  | LIDENT x | UIDENT x -> Some x
  | TYPE_VAR x -> Some ("?" ^ x)
  | SPEC title -> Some ("spec " ^ title)
  | CASE -> Some "case" | SOME -> Some "some" | DOUBLE -> Some "double"
  | ENSURE -> Some "ensure" | DO -> Some "do"
  | ARROW -> Some "->" | EQEQ -> Some "==" | RESULT -> Some "<<"
  | LT -> Some "<" | LE -> Some "<=" | GT -> Some ">" | GE -> Some ">="
  | EQUIV -> Some "~~"
  | DOTDOT -> Some ".." | CONCAT -> Some "++"
  | PLUS -> Some "+" | MINUS -> Some "-" | TIMES -> Some "*"
  | DIV -> Some "/" | MOD -> Some "%"
  | EQUAL -> Some "=" | COLON -> Some ":" | COMMA -> Some ","
  | DOT -> Some "." | BAR -> Some "|" | QUESTION -> Some "?" | CARET -> Some "^"
  | LPAREN -> Some "(" | RPAREN -> Some ")"
  | LBRACE -> Some "{" | RBRACE -> Some "}"
  | LBRACKET -> Some "[" | RBRACKET -> Some "]"
  | EOF -> None

(* The comparison operators, which are valid only in ord ? a < b. *)
let is_comparison = function
  | LT | LE | GT | GE | EQUIV -> true
  | _ -> false

let keyword_or_ident = function
  | "do" -> DO
  | "case" -> CASE
  | "some" -> SOME
  | "ensure" -> ENSURE
  | "double" -> DOUBLE
  | name -> LIDENT name

(* The position of the character at [offset] in the current lexeme. *)
let position_in_lexeme lexbuf offset : Diagnostic.position =
  let start = Lexing.lexeme_start_p lexbuf in
  let text = Lexing.lexeme lexbuf in
  let line = ref start.pos_lnum and bol = ref start.pos_bol in
  for i = 0 to offset - 1 do
    if text.[i] = '\n' then begin
      incr line;
      bol := start.pos_cnum + i + 1
    end
  done;
  { filename = start.pos_fname;
    line = !line;
    column = start.pos_cnum + offset - !bol + 1 }

(* A spec title (spec, section 3.6): reject '}' and backticks, collapse every
   run of whitespace to one space, trim, and require it to be non-empty.
   [title] starts at [offset] in the current lexeme. *)
let spec_title lexbuf offset title =
  String.iteri (fun i c ->
    if c = '}' || c = '`' then
      error (Diagnostic.Invalid_spec_title_character {
        character = String.make 1 c;
        position = position_in_lexeme lexbuf (offset + i);
      }))
    title;
  let words =
    String.split_on_char ' '
      (String.map (function '\t' | '\r' | '\n' -> ' ' | c -> c) title)
    |> List.filter (fun w -> w <> "")
  in
  if words = [] then
    error (Diagnostic.Missing_spec_title {
      position = position_of (Lexing.lexeme_start_p lexbuf);
    });
  String.concat " " words

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
let number = digit+ ('.' digit+)? exponent?
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
      let title = spec_title lexbuf 4 title in
      skip_newlines lexbuf (Lexing.lexeme lexbuf);
      SPEC title
    }
  | "spec" {
      error (Diagnostic.Missing_spec_title {
        position = position_of (Lexing.lexeme_start_p lexbuf);
      })
    }

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
  (* The first occurrence of a type variable (spec, section 4.7). Like a
     label, it is one token, so "? A" is not a type variable. *)
  | '?' (uident_start uident_char* as name) { TYPE_VAR name }

  | "->" { ARROW }
  | "==" { EQEQ }
  (* Comparisons under an ordering (spec, section 6.2). *)
  | "<=" { LE }
  | ">=" { GE }
  | "~~" { EQUIV }
  | '<' { LT }
  | '>' { GT }
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
  (* ^name pins a value in a pattern (spec, section 9); provisional. *)
  | '^' { CARET }
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
