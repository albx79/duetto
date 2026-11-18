(* A position in a source file as shown to the user: lines and columns
   count from 1. Used both by diagnostics and by AST locations, so that a
   check run on the AST can name the file as a parse error does. *)
type t = {
  filename : string;
  line : int;
  column : int;
}
[@@deriving show]

let of_lexing (pos : Lexing.position) = {
  filename = pos.pos_fname;
  line = pos.pos_lnum;
  column = pos.pos_cnum - pos.pos_bol + 1;
}

let to_string pos = Printf.sprintf "%s:%d:%d" pos.filename pos.line pos.column
