(* Types as they appear in signatures and in the built-in environment:
   immutable, with generalization variables, concrete label sets and Never
   (formal core, section 2.1). Inference uses its own mutable types, and
   converts to and from these at instantiation and generalization. *)

type ty =
  | Num
  | String
  | Never
  (* A concrete label set, without the leading quote: ["lt"; "eq"]. It has
     no duplicates; the order is only for printing. *)
  | Labels of string list
  | List of ty
  (* Fields have distinct names; the order is only for printing. *)
  | Record of (string * ty) list * row
  (* A zero-argument function () -> T is a function from the empty record
     (spec, section 4.6), so its parameters are [Record ([], Closed)]. *)
  | Function of ty list * ty
  (* A generalization variable X. The number only identifies it: printing
     names variables by first occurrence. *)
  | Var of int

and row =
  | Closed
  (* A generalization row variable R. *)
  | Row_var of int

(* Every variable is quantified at the top: signatures are prenex (spec,
   section 4.7). *)
type t = {
  body : ty;
  (* The fields each row variable must not contain (formal core, section
     3.3), for every row variable in [body]. A row lacks at least the
     fields next to it wherever it occurs, but a signature keeps the lacks
     set its spec gave the row, which may be larger (section 6.4). *)
  lacks : (int * string list) list;
}

(* A scheme whose row variables lack exactly the fields next to them, as
   for the built-ins. *)
let of_ty body =
  let lacks = Hashtbl.create 8 in
  let rec collect = function
    | Num | String | Never | Labels _ | Var _ -> ()
    | List t -> collect t
    | Record (fields, row) ->
        List.iter (fun (_, t) -> collect t) fields;
        (match row with
         | Closed -> ()
         | Row_var r ->
             let known = Option.value ~default:[] (Hashtbl.find_opt lacks r) in
             let added = List.filter (fun (f, _) -> not (List.mem f known)) fields in
             Hashtbl.replace lacks r (known @ List.map fst added))
    | Function (params, result) ->
        List.iter collect params;
        collect result
  in
  collect body;
  { body; lacks = List.sort compare (List.of_seq (Hashtbl.to_seq lacks)) }

(* Names by order of first occurrence: X, Y, Z, X1, X2, ... for types,
   and R, R1, R2, ... for rows, so the two never clash. *)
let type_var_name = function
  | 0 -> "X"
  | 1 -> "Y"
  | 2 -> "Z"
  | n -> "X" ^ string_of_int (n - 2)

let row_var_name = function
  | 0 -> "R"
  | n -> "R" ^ string_of_int n

(* Prints a type in Duetto's type syntax, so that a signature reads like
   source (spec, section 12.5). A variable is written with "?" at its first
   occurrence, as in (?X) -> X. A row variable that occurs once is written
   "..", since nothing else refers to it. Lacks sets are not printed: the
   surface syntax has no way to write them. *)
let to_string { body; lacks = _ } =
  let row_occurrences = Hashtbl.create 8 in
  let rec count = function
    | Num | String | Never | Labels _ | Var _ -> ()
    | List t -> count t
    | Record (fields, row) ->
        List.iter (fun (_, t) -> count t) fields;
        (match row with
         | Closed -> ()
         | Row_var r ->
             let n = Option.value ~default:0 (Hashtbl.find_opt row_occurrences r) in
             Hashtbl.replace row_occurrences r (n + 1))
    | Function (params, result) ->
        List.iter count params;
        count result
  in
  count body;
  let type_names = Hashtbl.create 8 in
  let row_names = Hashtbl.create 8 in
  let name names make id =
    match Hashtbl.find_opt names id with
    | Some name -> name
    | None ->
        let name = make (Hashtbl.length names) in
        Hashtbl.add names id name;
        "?" ^ name
  in
  (* A buffer, not string concatenation: names are given in the order they
     are printed, and OCaml evaluates the operands of ^ right to left. *)
  let buffer = Buffer.create 64 in
  let add = Buffer.add_string buffer in
  let add_list f items =
    List.iteri (fun i item -> if i > 0 then add ", "; f item) items
  in
  let rec ty = function
    | Num -> add "Num"
    | String -> add "String"
    | Never | Labels [] -> add "Never"
    | Labels labels -> add (String.concat " | " (List.map (fun l -> "'" ^ l) labels))
    | List t ->
        add "[";
        ty t;
        add "]"
    | Record ([], Closed) -> add "{}"
    | Record (fields, row) ->
        add "{ ";
        add_list (fun (f, t) -> add f; add ": "; ty t) fields;
        (match row with
         | Closed -> ()
         | Row_var r ->
             if fields <> [] then add ", ";
             add "..";
             if Hashtbl.find row_occurrences r > 1 then add (name row_names row_var_name r));
        add " }"
    (* A union member never needs parentheses: only labels form unions
       here, and a function's result extends to the end of the type. *)
    | Function (params, result) ->
        add "(";
        (match params with
         | [Record ([], Closed)] -> ()
         | _ -> add_list ty params);
        add ") -> ";
        ty result
    | Var x -> add (name type_names type_var_name x)
  in
  ty body;
  Buffer.contents buffer
