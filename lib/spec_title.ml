(* A spec title as the lexer produces it (spec, sections 3.6 and 10.9):
   free text and marked interface names, each with its start and end. *)

type segment =
  (* Free text, with every run of whitespace collapsed to one space. Text
     next to a mark keeps its space, so that the title reads as written. *)
  | Text of string
  (* `m.Ordering`: an interface name, with the value path before it. *)
  | Mark of string list * string

type t = (segment * Lexing.position * Lexing.position) list

let segment_to_string = function
  | Text s -> s
  | Mark (path, name) -> "`" ^ String.concat "." (path @ [name]) ^ "`"

(* The title as written, with its marks in backticks. Since text cannot
   contain backticks, this determines the segments. *)
let to_string (title : t) =
  String.concat "" (List.map (fun (s, _, _) -> segment_to_string s) title)
