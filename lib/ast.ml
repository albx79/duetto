type struct_entry =
  | Field of string * expr
  | Local of string * expr
  | Result of expr

and expr =
  | Num of string
  | Ident of string
  | Proj of expr * string
  | Struct of struct_entry list
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Div of expr * expr
[@@deriving show]
