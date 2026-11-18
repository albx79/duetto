type location = {
  start_pos : Position.t;
  end_pos : Position.t;
}
[@@deriving show]

let location_of_lexing_positions (start_pos : Lexing.position) (end_pos : Lexing.position)
  : location =
  {
    start_pos = Position.of_lexing start_pos;
    end_pos = Position.of_lexing end_pos;
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
    (* A type name, reached through a path of value names: Bool is
       ([], "Bool"), m.Bool is (["m"], "Bool"). Types are members of
       records, not of other types, so only the last segment is a type. *)
    | Type_ref of string list * string
    (* ?A: the first occurrence of a type variable. Later occurrences are
       bare names, parsed as Type_ref and resolved later (spec, 4.7). *)
    | Type_var of string
    (* Result(A, E), m.Ordering(Num): a type constructor, reached through a
       path like Type_ref, applied to at least one argument. *)
    | Type_apply of string list * string * type_expr list
    | Type_record of (string * type_expr) list
    (* { f: T, .. }, { f: T, ..?R } or { f: T, ..R }: a record with at least
       these fields (spec, section 4.4). *)
    | Type_open_record of (string * type_expr) list * row
    (* 'a, a label singleton type (spec, section 4.2). *)
    | Type_label of string
    (* T1 | ... | Tn with n >= 2, in source order; which members are allowed
       is checked later (spec, section 9). *)
    | Type_union of type_expr list
    (* [T] (spec, section 4.5). *)
    | Type_list of type_expr
    (* (T1, ..., Tn) -> R (spec, section 4.1); () -> R takes no arguments. *)
    | Type_function of type_expr list * type_expr

  (* The rest of an open record type. *)
  and row =
    | Anonymous_row            (* .., a fresh unnamed row variable *)
    | Row_var of string        (* ..?R, the first occurrence of R *)
    | Row_ref of string        (* ..R, a later occurrence *)

  (* A spec's title: free text and the interface names it marks in
     backticks, which make it a law spec (spec, sections 3.6 and 10.9). *)
  and spec_title = title_segment list
  and title_segment = title_segment_node wrapped
  and title_segment_node =
    | Title_text of string
    (* `m.Ordering`: the value path, then the type name. *)
    | Title_mark of string list * string

  and comparison =
    | Less            (* < *)
    | Less_or_equal   (* <= *)
    | Greater         (* > *)
    | Greater_or_equal (* >= *)
    | Equivalent      (* ~~ *)

  and struct_entry = struct_entry_node wrapped
  and struct_entry_node =
    | Field of string * expr
    | Local of string * expr
    (* Name(Params): T and Name(Params) = T (spec, section 3.8). Types exist
       only at compile time: they are not part of a record's runtime value. *)
    | Type_field of string * string list * type_expr
    | Type_local of string * string list * type_expr
    | Ensure of expr
    | Do of expr
    (* A spec entry: its title and its body's entries, which are locals and
       ensures only (spec, section 7). *)
    | Spec of spec_title * struct_entry list

  (* A branch of a case (spec, sections 6.3 and 9). *)
  and case_branch = {
    pattern : pattern;
    body : expr;
  }

  (* One pattern language for case branches and the stubs of doubles
     (spec, section 9). *)
  and pattern = pattern_node wrapped
  and pattern_node =
    | Label_pattern of string
    (* A number literal, with a leading "-" when the pattern is negative. *)
    | Num_pattern of string
    | String_pattern of string
    (* x: matches anything and binds it. *)
    | Binder of string
    (* ^x: matches the value of x, already in scope. *)
    | Pinned of string
    (* some(T): matches every value of T, binding nothing. *)
    | Some_pattern of type_expr
    (* { f: P, ... }: a record with exactly these fields. A field written
       alone, { f }, is parsed as { f: f }. *)
    | Record_pattern of (string * pattern) list
    (* { f: P, ..., .. }: a record with at least these fields. *)
    | Open_record_pattern of (string * pattern) list

  (* A stub of a double: a function name, a pattern per argument, and the
     responses to successive calls, the last of which repeats (spec,
     section 11). *)
  and stub = {
    stub_name : string;
    arguments : pattern list;
    responses : expr list;
  }

  and expr = expr_node wrapped
  and expr_node =
    | Num of string
    | String of string
    | Label of string
    | Case of expr * case_branch list
    | Double of stub list
    | Ident of string
    | Proj of expr * string
    | Call of expr * expr list
    | Lambda of string list * expr
    | Some_val of type_expr
    (* every(T): the subject of a law spec (spec, section 10.9). *)
    | Every of type_expr
    (* A brace group without a result: its fields are its value. *)
    | Record of struct_entry list
    (* A brace group ending with <<e: its value is e (spec, section 3.3). *)
    | Block of struct_entry list * expr
    | List of expr list
    | Concat of expr * expr
    | Eq of expr * expr
    (* ord ? a < b (spec, section 6.2): ordering, operator, operands. *)
    | Compare of expr * comparison * expr * expr
    (* -e. Number literals are never negative: -1 is Neg (Num "1"). *)
    | Neg of expr
    | Add of expr * expr
    | Sub of expr * expr
    | Mul of expr * expr
    | Div of expr * expr
    | Mod of expr * expr
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
