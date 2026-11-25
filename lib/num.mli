type t
val equal : t -> t -> bool
val add : t -> t -> t

(** the wheel of rationals has only one infinity, so neg(1/0) is still 1/0 *) 
val neg : t -> t
val sub : t -> t -> t
val mul : t -> t -> t

(** division never fails: zero/zero is bottom, and x/0 is infinity *)
val div : t -> t -> t

(** the unary inverse as defined by Carlström (2004) *)
val inv : t -> t
val to_string : t -> string
val of_ints : int -> int -> t
