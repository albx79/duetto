type t = { 
  num : Z.t; 
  den : Z.t;
}

let infty = { num = Z.one; den = Z.zero; }
let bottom = { num = Z.zero; den = Z.zero; }

let normalise value = 
  if Z.equal value.den Z.zero
  then 
    if Z.equal value.num Z.zero 
    then bottom
    else infty
  else
    let the_gcd = Z.gcd value.num value.den in 
    let sign = (Z.sign value.num) * (Z.sign value.den) in 
    {
      num = (
        let tmp_num = Z.(abs (value.num / the_gcd))
        in if sign < 0 then Z.neg tmp_num else tmp_num
      );
      den = Z.(abs (value.den / the_gcd));
    }

let of_ints n d = 
  let value = {
    num = Z.of_int n;
    den = Z.of_int d;
  } 
  in normalise value

let equal l r = (Z.equal l.num r.num) && (Z.equal l.den r.den)

let make num den = normalise { num; den }

let neg { num = a; den = b } = Z.(make (-a) b)
let inv { num = a; den = b } = make b a
let add { num = a; den = b } { num = c; den = d } = Z.(make (a*d + b*c) (b*d))
let sub lhs rhs = add lhs (neg rhs)
let mul { num = a; den = b } { num = c; den = d } = Z.(make (a*c) (b*d))
let div lhs rhs = mul lhs (inv rhs)

let floor { num; den } = 
  if Z.equal den Z.zero 
  then { num; den }
  else (make (Z.fdiv num den) Z.one)

let rem a b = sub a (mul b (floor (div a b)))

let to_fraction_string value = Printf.sprintf "%s/%s" (Z.to_string value.num) (Z.to_string value.den)

module IntMap = Map.Make(Z)
let ten = Z.of_int 10

let to_string { num; den } =
  if den = Z.zero then
  if num = Z.zero then "⊥" else "∞"
  else
    let sign = if Z.sign num < 0 then "-" else "" in
    let n = Z.abs num in
    let d = den in
    let int_part = Z.to_string Z.(n / d) in
    let rem = Z.(n mod d) in
    if rem = Z.zero then
      sign ^ int_part
    else
      let buf = Buffer.create 32 in
      let rec loop r idx seen =
        if r = Z.zero then
          sign ^ int_part ^ "." ^ Buffer.contents buf
        else
          match IntMap.find_opt r seen with
          | Some start_idx ->
              let frac = Buffer.contents buf in
              let non_rep = String.sub frac 0 start_idx in
              let rep = String.sub frac start_idx (String.length frac - start_idx) in
              Printf.sprintf "%s%s.%s(%s)" sign int_part non_rep rep
          | None ->
              let seen' = IntMap.add r idx seen in
              let r10 = Z.(r * ten) in
              Buffer.add_string buf (Z.to_string Z.(r10 / d));
              loop Z.(r10 mod d) (idx + 1) seen'
      in
      loop rem 0 IntMap.empty

let ( let* ) = Option.bind

let is_valid_digits s = String.length s > 0 && s |> String.for_all (fun (d) -> d >= '0' && d <= '9')
let is_valid_exp exp = 
  let end_idx = String.length exp in
  ((String.starts_with ~prefix:"-" exp || String.starts_with ~prefix:"+" exp) && is_valid_digits (String.sub exp 1 (end_idx-1)))
  || is_valid_digits exp

let number_string_and_exp (s: string) : (string * int) option = 
  match String.split_on_char 'e' s with 
  | [number] -> Some (number, 0)
  | [number; exp] -> if is_valid_exp exp
    then (int_of_string_opt exp) |> Option.map (fun e -> (number, e))
    else None
| _ -> None

let whole_string_and_len_of_dec s = match s |> String.split_on_char '.' with 
  | [whole] -> if is_valid_digits whole then Some (whole, 0) else None
  | [whole; decimals] -> if is_valid_digits whole && is_valid_digits decimals 
    then Some (whole ^ decimals, String.length decimals)
    else None 
  | _ -> None

let of_string_opt s = 
  let input = String.lowercase_ascii s in
  let* (number_str, exp) = number_string_and_exp input in
  let* (whole, dec_digits) = whole_string_and_len_of_dec number_str in
  let whle = Z.of_string whole in
  let (k_pos, k_neg) = if exp >= 0 then (exp, 0) else (0, -exp)
  in let num = Z.( whle * (pow ten k_pos) )
  and den = Z.pow ten (k_neg + dec_digits)
  in Some (normalise { num; den })  

let of_string s = match of_string_opt s with 
  | Some n -> n
  | None -> failwith ("Invalid number " ^ s)
