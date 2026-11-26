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

val to_fraction_string : t -> string
val to_string : t -> string
val of_ints : int -> int -> t
val of_string : string -> t
val of_string_opt : string -> t option

(** For infinity and bottom, returns the input value *)
val floor : t -> t

(** The _floored_ remainder: the result has the sign of the divisor *)
val rem : t -> t -> t