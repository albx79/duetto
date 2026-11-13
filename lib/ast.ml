type type_expr =
  | Type_ident of string
  | Type_apply of string * type_expr list
  | Type_record of (string * type_expr) list

and struct_entry =
  | Field of string * expr
  | Local of string * expr
  | Result of expr

and expr =
  | Num of string
  | Ident of string
  | Proj of expr * string
  | Some_val of type_expr
  | Struct of struct_entry list
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Div of expr * expr
[@@deriving show]
