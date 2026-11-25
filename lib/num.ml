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

let add { num = a; den = b } { num = c; den = d } = Z.(make (a*d + b*c) (b*d))
let sub { num = a; den = b } { num = c; den = d } = failwith "TODO"
let div { num = a; den = b } { num = c; den = d } = failwith "TODO"
let mul { num = a; den = b } { num = c; den = d } = failwith "TODO"
let neg { num = a; den = b } = failwith "TODO"
let inv { num = a; den = b } = failwith "TODO"

let to_string value = Printf.sprintf "%s/%s" (Z.to_string value.num) (Z.to_string value.den)
