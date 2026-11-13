type position = {
  line : int;
  column : int;
}
[@@deriving show]

type location = {
  start_pos : position;
  end_pos : position;
}
[@@deriving show]

let position_of_lexing (pos : Lexing.position) : position = {
  line = pos.pos_lnum;
  column = pos.pos_cnum - pos.pos_bol + 1;
}

let location_of_lexing_positions (start_pos : Lexing.position) (end_pos : Lexing.position)
  : location =
  {
    start_pos = position_of_lexing start_pos;
    end_pos = position_of_lexing end_pos;
  }

let dummy_location =
  {
    start_pos = { line = 0; column = 0 };
    end_pos = { line = 0; column = 0 };
  }

type 'a located = {
  node : 'a;
  loc : location;
}
[@@deriving show]

(* How each node carries its location: [Located_wrap] keeps one, and
   [Unit_wrap] keeps nothing, so tests can write expected trees directly. *)
module type WRAP = sig
  type loc
  type 'a t

  val wrap : loc -> 'a -> 'a t
  val of_lexing_positions : Lexing.position -> Lexing.position -> loc
  val pp : (Format.formatter -> 'a -> unit) -> Format.formatter -> 'a t -> unit
end

(* The AST is defined only here. *)
module Make (W : WRAP) = struct
  type loc = W.loc
  type 'a wrapped = 'a W.t

  let pp_wrapped = W.pp

  type type_expr = type_expr_node wrapped
  and type_expr_node =
    | Type_ident of string
    | Type_apply of string * type_expr list
    | Type_record of (string * type_expr) list

  and struct_entry = struct_entry_node wrapped
  and struct_entry_node =
    | Field of string * expr
    | Local of string * expr
    | Result of expr

  and expr = expr_node wrapped
  and expr_node =
    | Num of string
    | String of string
    | Ident of string
    | Proj of expr * string
    | Call of expr * expr list
    | Lambda of string list * expr
    | Some_val of type_expr
    | Struct of struct_entry list
    | List of expr list
    | Concat of expr * expr
    | Add of expr * expr
    | Sub of expr * expr
    | Mul of expr * expr
    | Div of expr * expr
  [@@deriving show]

  let with_loc = W.wrap
  let of_lexing_positions = W.of_lexing_positions
end

(* What the parser is parameterised over: an AST together with its wrapper.
   The signature is derived from [Make], so the types are not repeated. *)
module type S = sig
  module W : WRAP
  include module type of Make (W)
end

module Located_wrap = struct
  type loc = location
  type 'a t = 'a located

  let wrap loc node = { node; loc }
  let of_lexing_positions = location_of_lexing_positions

  let pp pp_a fmt { node; loc } =
    Format.fprintf fmt "{ node = %a; loc = %a }" pp_a node pp_location loc
end

module Unit_wrap = struct
  type loc = unit
  type 'a t = 'a

  let wrap () node = node
  let of_lexing_positions _ _ = ()
  let pp pp_a fmt node = pp_a fmt node
end

module Located = struct
  module W = Located_wrap
  include Make (W)
end

module Unit = struct
  module W = Unit_wrap
  include Make (W)
end
