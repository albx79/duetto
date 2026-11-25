module N = Duetto.Num

let failures = ref 0

let check name actual expected =
  let actual = N.to_string actual in
  if actual <> expected then begin
    incr failures;
    Printf.printf "FAIL %s\n  expected: %s\n  actual:   %s\n" name expected actual
  end

let () =
  let q = N.of_ints in
  check "already normal" (q 1 2) "1/2";
  check "common factor" (q 2 4) "1/2";

  check "already normal zero" (q 0 1) "0/1";
  check "normalise zero" (q 0 42) "0/1";
  check "negative den zero" (q 0 (-1)) "0/1";

  check "negative num" (q (-2) 4) "-1/2";
  check "negative den" (q 2 (-4)) "-1/2";
  check "negative both" (q (-2) (-4)) "1/2";

  check "already normal infty" (q 1 0) "1/0";
  check "normalize infty" (q 42 0) "1/0";
  check "negative infty" (q (-42) 0) "1/0";

  check "bottom" (q 0 0) "0/0";

  check "add 1/2 1/2" (N.add (q 1 2) (q 1 2)) "1/1";
  check "add negative" (N.add (q 1 2) (q (-1) 2)) "0/1";
  check "add infty" (N.add (q 1 2) (q 1 0)) "1/0";
  check "add bottom" (N.add (q 1 2) (q 0 0)) "0/0";
  check "add bottom rhs" (N.add (q 0 0) (q 1 2)) "0/0";

  check "neg 1/2" (N.neg (q 1 2)) "-1/2";
  check "neg -1/2" (N.neg (q (-1) 2)) "1/2";
  check "neg zero" (N.neg (q 0 (-42))) "0/1";
  check "neg infty" (N.neg (q (-42) 0)) "1/0";

  check "sub 1/2 1/6" (N.sub (q 1 2) (q 1 6)) "1/3";
  check "sub infty" (N.sub (q 1 2) (q 1 0)) "1/0";
  check "sub infty infty" (N.sub (q 1 0) (q 1 0)) "0/0";
  check "sub bottom" (N.sub (q 1 2) (q 0 0)) "0/0";
  check "sub bottom lhs" (N.sub (q 0 0) (q 1 2)) "0/0";

  check "mul 1/2 1/2" (N.mul (q 1 2) (q 1 2)) "1/4";
  check "mul negative" (N.mul (q 1 2) (q (-1) 2)) "-1/4";
  check "mul infty" (N.mul (q 1 2) (q 1 0)) "1/0";
  check "mul zero infty" (N.mul (q 0 1) (q 1 0)) "0/0";
  check "mul bottom" (N.mul (q 1 2) (q 0 0)) "0/0";
  check "mul bottom rhs" (N.mul (q 0 0) (q 1 2)) "0/0";

  check "inv 1/2" (N.inv (q 1 2)) "2/1";
  check "inv zero" (N.inv (q 0 1)) "1/0";
  check "inv infty" (N.inv (q 1 0)) "0/1";
  check "inv bottom" (N.inv (q 0 0)) "0/0";

  check "div 1/2 1/2" (N.div (q 1 2) (q 1 2)) "1/1";
  check "div negative den" (N.div (q 1 2) (q (-1) 3)) "-3/2";
  check "div by zero is infty" (N.div (q 1 1) (q 0 1)) "1/0";
  check "div zero by zero is bottom" (N.div (q 0 1) (q 0 1)) "0/0";

  check "preserve precision" (N.mul (q 1 3) (q 3 1)) "1/1";
    
  if !failures > 0 then exit 1 else print_endline "num tests passed"
