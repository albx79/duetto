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

module type WRAP = sig
  type loc
  type 'a t

  val wrap : loc -> 'a -> 'a t
  val pp : (Format.formatter -> 'a -> unit) -> Format.formatter -> 'a t -> unit
end

module type LOC = sig
  type t
  val of_lexing_positions : Lexing.position -> Lexing.position -> t
end

module type S = sig
  type loc
  type 'a wrapped

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
    | Some_val of type_expr
    | Struct of struct_entry list
    | List of expr list
    | Concat of expr * expr
    | Add of expr * expr
    | Sub of expr * expr
    | Mul of expr * expr
    | Div of expr * expr

  val with_loc : loc -> 'a -> 'a wrapped
  val of_lexing_positions : Lexing.position -> Lexing.position -> loc

  val pp_expr : Format.formatter -> expr -> unit
  val show_expr : expr -> string
  val pp_type_expr : Format.formatter -> type_expr -> unit
  val show_type_expr : type_expr -> string
  val pp_struct_entry : Format.formatter -> struct_entry -> unit
  val show_struct_entry : struct_entry -> string
end

module Make (W : WRAP) (L : LOC with type t = W.loc) :
  S with type loc = W.loc and type 'a wrapped = 'a W.t =
struct
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
  let of_lexing_positions = L.of_lexing_positions
end

module Located_wrap = struct
  type loc = location
  type 'a t = 'a located

  let wrap loc node = { node; loc }

  let pp pp_a fmt { node; loc } =
    Format.fprintf fmt "{ node = %a; loc = %a }" pp_a node pp_location loc
end

module Unit_wrap = struct
  type loc = unit
  type 'a t = 'a

  let wrap () node = node
  let pp pp_a fmt node = pp_a fmt node
end

module Located = Make (Located_wrap) (struct
  type t = location
  let of_lexing_positions = location_of_lexing_positions
end)

module Unit = Make (Unit_wrap) (struct
  type t = unit
  let of_lexing_positions _ _ = ()
end)
