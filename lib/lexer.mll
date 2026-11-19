{
open Tokens

(* Columns count characters, not bytes. Source text is read as UTF-8, and
   non-ASCII characters can only occur in strings, comments and
   spec titles. After such a lexeme, [account_for] moves [pos_bol] forward
   by one for each continuation byte on the current line, so that
   [pos_cnum - pos_bol], which [Position.of_lexing] uses, counts characters.
   [pos_bol] is therefore not a byte offset; nothing else uses it. *)
let is_continuation_byte c = Char.code c land 0xC0 = 0x80

(* The Lexing position of the character at [offset] in the current lexeme,
   which may span lines, as a spec title does. *)
let lexing_position_in_lexeme lexbuf offset : Lexing.position =
  let start = Lexing.lexeme_start_p lexbuf in
  let text = Lexing.lexeme lexbuf in
  let line = ref start.pos_lnum and bol = ref start.pos_bol in
  for i = 0 to offset - 1 do
    if text.[i] = '\n' then begin
      incr line;
      bol := start.pos_cnum + i + 1
    end
    else if is_continuation_byte text.[i] then incr bol
  done;
  { start with pos_lnum = !line; pos_bol = !bol; pos_cnum = start.pos_cnum + offset }

(* Moves the end of the current lexeme past its newlines and non-ASCII
   characters. [Lexing.new_line] only handles a lexeme that ends with its
   one newline. *)
let account_for lexbuf =
  let text = Lexing.lexeme lexbuf in
  let end_pos = lexing_position_in_lexeme lexbuf (String.length text) in
  lexbuf.Lexing.lex_curr_p <- end_pos

let position_in_lexeme lexbuf offset =
  Position.of_lexing (lexing_position_in_lexeme lexbuf offset)

let error e = raise (Diagnostic.Error e)

let invalid_utf8 lexbuf text i =
  error (Diagnostic.Invalid_utf8 {
    byte = Char.code text.[i];
    position = position_in_lexeme lexbuf i;
  })

let validate_utf8 lexbuf =
  let text = Lexing.lexeme lexbuf in
  let rec scan i =
    if i < String.length text then begin
      let decoded = String.get_utf_8_uchar text i in
      if not (Uchar.utf_decode_is_valid decoded) then invalid_utf8 lexbuf text i;
      scan (i + Uchar.utf_decode_length decoded)
    end
  in
  scan 0

let keyword_as_name lexbuf keyword =
  error (Diagnostic.Keyword_as_name {
    keyword;
    position = Position.of_lexing (Lexing.lexeme_start_p lexbuf);
  })

(* Whether a spec title starts with "=" or ":": then "spec" is a name in
   a local or a field, not the start of a spec entry. *)
let starts_like_a_binding title =
  match String.trim title with
  | "" -> false
  | t -> t.[0] = '=' || t.[0] = ':'

(* Reports the first character of the current lexeme, a misspelled name,
   that [bad] accepts. *)
let bad_character_in_name lexbuf bad =
  let lexeme = Lexing.lexeme lexbuf in
  let rec find i = if bad lexeme.[i] then i else find (i + 1) in
  let i = find 0 in
  error (Diagnostic.Unexpected_character {
    character = String.make 1 lexeme.[i];
    position = position_in_lexeme lexbuf i;
  })

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

(* The spelling of a keyword token that would otherwise be a name, as
   returned by [keyword_or_ident]. *)
let keyword_name = function
  | DO -> Some "do" | CASE -> Some "case" | SOME -> Some "some"
  | EVERY -> Some "every" | ENSURE -> Some "ensure" | DOUBLE -> Some "double"
  | _ -> None

let name_token name = LIDENT name

(* Entry keywords followed by an expression, as in "ensure x == 1", and the
   tokens that end an entry. "{ ensure }" reads as a missing expression
   rather than as a punned field named ensure. *)
let takes_expression = function ENSURE | DO -> true | _ -> false
let ends_entry = function COMMA | RBRACE | EOF -> true | _ -> false

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
      position = Position.of_lexing (Lexing.lexeme_start_p lexbuf);
    });
  segments
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
(* One non-ASCII character in well-formed UTF-8. *)
let utf8_continuation = ['\x80'-'\xbf']
let utf8_multibyte =
    ['\xc2'-'\xdf'] utf8_continuation
  | ('\xe0' ['\xa0'-'\xbf'] | ['\xe1'-'\xec' '\xee'-'\xef'] utf8_continuation
    | '\xed' ['\x80'-'\x9f']) utf8_continuation
  | ('\xf0' ['\x90'-'\xbf'] | ['\xf1'-'\xf3'] utf8_continuation
    | '\xf4' ['\x80'-'\x8f']) utf8_continuation utf8_continuation

rule token = parse
  | whitespace { token lexbuf }
  | '\n' {
      Lexing.new_line lexbuf;
      token lexbuf
    }
  (* Reserved tokens (spec, section 3.7). The ones starting with '#' also
     match the rest of the line: otherwise the comment rule below would be
     the longest match, and "#!x" would be read as a comment. With equal
     lengths, the earlier rule wins. Inside a comment they are just text. *)
  | (("#!" | "#[" | "#_") as token) [^ '\n']*
  | ("]#" as token) {
        error (Diagnostic.Reserved_token {
          token;
          position = Position.of_lexing (Lexing.lexeme_start_p lexbuf);
        })
      }
  | "#" [^ '\n']* { validate_utf8 lexbuf; account_for lexbuf; token lexbuf }

  (* A spec title is free text up to the opening brace (spec, section 3.6).
     A title never starts with "=" or ":", so "spec = 1" and "spec : 1"
     use spec as a name. This is checked first, because the title would run
     on to the next "{" and fail with a confusing error, or none. *)
  | "spec" ([' ' '\t' '\r' '\n'] [^ '{']* as title) {
      validate_utf8 lexbuf;
      if starts_like_a_binding title then keyword_as_name lexbuf "spec";
      let title = spec_title lexbuf 4 title in
      account_for lexbuf;
      SPEC title
    }
  (* "spec" followed by neither whitespace nor "{", as in "spec:" or
     "f(spec)": it is used as a name. Name characters are left out, so
     that "specs" and "spec_x" remain names. *)
  | "spec" ([^ ' ' '\t' '\r' '\n' '{' 'a'-'z' 'A'-'Z' '0'-'9' '_'] | eof) {
      keyword_as_name lexbuf "spec"
    }
  | "spec" {
      error (Diagnostic.Missing_spec_title {
        position = Position.of_lexing (Lexing.lexeme_start_p lexbuf);
      })
    }

  | number as n { NUM n }
  | '"' {
      let start = Lexing.lexeme_start_p lexbuf in
      let s = string (Buffer.create 16) start lexbuf in
      lexbuf.lex_start_p <- start;
      STRING s
    }
  (* Value names and labels are snake_case, and type names are PascalCase
     (spec, section 3.8): "readFile" and "Foo_Bar" are errors, not two
     tokens. These rules are longer matches than the valid names. *)
  | '\'' lident_start lident_char* uident_start ident_char* {
      bad_character_in_name lexbuf (fun c -> c >= 'A' && c <= 'Z')
    }
  | '\'' (lident_start lident_char* as l) { LABEL l }
  | lident_start lident_char* uident_start ident_char* {
      bad_character_in_name lexbuf (fun c -> c >= 'A' && c <= 'Z')
    }
  | lident_start lident_char* as name { keyword_or_ident name }
  | uident_start uident_char* '_' ident_char* {
      bad_character_in_name lexbuf (fun c -> c = '_')
    }
  | uident_start uident_char* as name { UIDENT name }
  (* The first occurrence of a type variable (spec, section 4.7). Like a
     label, it is one token, so "? A" is not a type variable. *)
  | '?' uident_start uident_char* '_' ident_char* {
      bad_character_in_name lexbuf (fun c -> c = '_')
    }
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

  | utf8_multibyte as character {
      error (Diagnostic.Unexpected_character {
        character;
        position = Position.of_lexing (Lexing.lexeme_start_p lexbuf);
      })
    }
  | ['\x80'-'\xff'] as byte {
      error (Diagnostic.Invalid_utf8 {
        byte = Char.code byte;
        position = Position.of_lexing (Lexing.lexeme_start_p lexbuf);
      })
    }
  | _ as character {
      let character =
        if character < ' ' || character = '\x7f'
        then Printf.sprintf "\\x%02X" (Char.code character)
        else String.make 1 character
      in
      error (Diagnostic.Unexpected_character {
        character;
        position = Position.of_lexing (Lexing.lexeme_start_p lexbuf);
      })
    }

and string buf start = parse
  | '"' { Buffer.contents buf }
  | "\\\"" { Buffer.add_char buf '"'; string buf start lexbuf }
  | "\\\\" { Buffer.add_char buf '\\'; string buf start lexbuf }
  | "\\n" { Buffer.add_char buf '\n'; string buf start lexbuf }
  | "\\t" { Buffer.add_char buf '\t'; string buf start lexbuf }
  | '\\' ((utf8_multibyte | _) as c) {
      validate_utf8 lexbuf;
      error (Diagnostic.Invalid_escape {
        sequence = "\\" ^ c;
        position = Position.of_lexing (Lexing.lexeme_start_p lexbuf);
      })
    }
  | '\n' | eof {
      error (Diagnostic.Unterminated_string { position = Position.of_lexing start })
    }
  | [^ '"' '\\' '\n']+ as s {
      validate_utf8 lexbuf;
      account_for lexbuf;
      Buffer.add_string buf s;
      string buf start lexbuf
    }
