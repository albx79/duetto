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
  | SPEC title -> Some ("spec " ^ Spec_title.to_string title)
  | CASE -> Some "case" | SOME -> Some "some" | EVERY -> Some "every" | DOUBLE -> Some "double"
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
  | "every" -> EVERY
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

(* The Lexing position of the character at [offset] in the current lexeme. *)
let lexing_position_in_lexeme lexbuf offset : Lexing.position =
  let start = Lexing.lexeme_start_p lexbuf in
  let text = Lexing.lexeme lexbuf in
  let line = ref start.pos_lnum and bol = ref start.pos_bol in
  for i = 0 to offset - 1 do
    if text.[i] = '\n' then begin
      incr line;
      bol := start.pos_cnum + i + 1
    end
  done;
  { start with pos_lnum = !line; pos_bol = !bol; pos_cnum = start.pos_cnum + offset }

let is_lident_start c = (c >= 'a' && c <= 'z') || c = '_'
let is_lident_char c = is_lident_start c || (c >= '0' && c <= '9')
let is_uident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

(* The contents of a mark: a type name, optionally after a value path, as
   in Ordering or m.Ordering. *)
let parse_mark text =
  let all p s = String.length s > 0 && String.for_all p s in
  match List.rev (String.split_on_char '.' text) with
  | name :: rev_path
    when String.length name > 0
         && name.[0] >= 'A' && name.[0] <= 'Z' && all is_uident_char name
         && List.for_all (fun p -> all is_lident_char p && is_lident_start p.[0]) rev_path ->
      Some (List.rev rev_path, name)
  | _ -> None

(* A spec title (spec, sections 3.6 and 10.9): free text and marks in
   backticks. Rejects '}', checks each mark, collapses every run of
   whitespace in the text to one space, trims the title's ends, and requires
   it to be non-empty. [title] starts at [offset] in the current lexeme. *)
let spec_title lexbuf offset title : Spec_title.t =
  let n = String.length title in
  let pos i = lexing_position_in_lexeme lexbuf (offset + i) in
  let normalise s =
    let buf = Buffer.create (String.length s) in
    let space = ref false in
    String.iter (fun c ->
      match c with
      | ' ' | '\t' | '\r' | '\n' -> space := true
      | c ->
          if !space then Buffer.add_char buf ' ';
          space := false;
          Buffer.add_char buf c)
      s;
    if !space then Buffer.add_char buf ' ';
    Buffer.contents buf
  in
  (* Split into text and marks, from [i]; [start] is where the current text
     began. *)
  let rec split i start acc =
    let text_until j acc =
      if j > start then (Spec_title.Text (normalise (String.sub title start (j - start))), pos start, pos j) :: acc
      else acc
    in
    if i >= n then List.rev (text_until n acc)
    else
      match title.[i] with
      | '}' ->
          error (Diagnostic.Invalid_spec_title_character {
            character = "}";
            position = position_in_lexeme lexbuf (offset + i);
          })
      | '`' ->
          let close =
            match String.index_from_opt title (i + 1) '`' with
            | Some j -> j
            | None ->
                error (Diagnostic.Unclosed_title_mark {
                  position = position_in_lexeme lexbuf (offset + i);
                })
          in
          let text = String.sub title (i + 1) (close - i - 1) in
          (match parse_mark text with
           | Some (path, name) ->
               let acc = text_until i acc in
               split (close + 1) (close + 1)
                 ((Spec_title.Mark (path, name), pos i, pos (close + 1)) :: acc)
           | None ->
               error (Diagnostic.Invalid_title_mark {
                 text;
                 position = position_in_lexeme lexbuf (offset + i);
               }))
      | _ -> split (i + 1) start acc
  in
  let segments = split 0 0 [] in
  (* Trim the title's two ends, and drop text that is only a space. Text
     between marks keeps its spaces. *)
  let trim_text f = function
    | (Spec_title.Text s, a, b) :: rest -> (Spec_title.Text (f s), a, b) :: rest
    | l -> l
  in
  let drop_leading_space s =
    if String.length s > 0 && s.[0] = ' ' then String.sub s 1 (String.length s - 1) else s
  in
  let drop_trailing_space s =
    let n = String.length s in
    if n > 0 && s.[n - 1] = ' ' then String.sub s 0 (n - 1) else s
  in
  let segments = trim_text drop_leading_space segments in
  let segments = List.rev (trim_text drop_trailing_space (List.rev segments)) in
  let segments =
    List.filter (function (Spec_title.Text "", _, _) -> false | _ -> true) segments
  in
  if segments = [] then
    error (Diagnostic.Missing_spec_title {
      position = position_of (Lexing.lexeme_start_p lexbuf);
    });
  segments

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
