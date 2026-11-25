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
  
  if !failures > 0 then exit 1 else print_endline "num tests passed"
