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

let to_string value = Printf.sprintf "%s/%s" (Z.to_string value.num) (Z.to_string value.den)

let of_string_opt s = int_of_string_opt s |> Option.map (fun i -> of_ints i 1)
let of_string s = match of_string_opt s with 
  | Some n -> n
  | None -> failwith ("Invalid number " ^ s)
