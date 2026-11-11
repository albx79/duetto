type expr =
  | Num of string
  | Struct of (string * expr) list
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Div of expr * expr
[@@deriving show]
