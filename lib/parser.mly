%{
open A

let mk_loc start_pos end_pos =
  of_lexing_positions start_pos end_pos

let mk node start_pos end_pos =
  with_loc (mk_loc start_pos end_pos) node

(* What an entry is, for the checks that depend on the kind of brace group
   it is in (spec, sections 3.2 and 3.3). The parser cannot look inside the
   AST nodes it builds, since they are abstract here, so each entry rule
   returns its role and position along with the node. *)
type role =
  | Field_role of string        (* a field, including a punned one *)
  | Public_type_role of string  (* a public type, including a punned one *)
  | Do_role
  | Other_role                  (* locals, private types, ensure, spec *)

let diagnostic_position (pos : Lexing.position) : Diagnostic.position = {
  filename = pos.pos_fname;
  line = pos.pos_lnum;
  column = pos.pos_cnum - pos.pos_bol + 1;
}

let error e = raise (Diagnostic.Error e)

(* A brace group with a result is a block, and a block has no fields or
   public types. *)
let check_block_entries entries =
  List.iter (fun (role, position, _) ->
    match role with
    | Field_role name ->
        error (Diagnostic.Field_in_block { name; is_type = false; position })
    | Public_type_role name ->
        error (Diagnostic.Field_in_block { name; is_type = true; position })
    | Do_role | Other_role -> ())
    entries

(* A file is a static struct: it has no result and performs no action. *)
let check_file_entries entries result =
  (match result with
   | Some (_, position) -> error (Diagnostic.Result_in_file { position })
   | None -> ());
  List.iter (fun (role, position, _) ->
    match role with
    | Do_role -> error (Diagnostic.Do_in_file { position })
    | Field_role _ | Public_type_role _ | Other_role -> ())
    entries

let nodes entries = List.map (fun (_, _, entry) -> entry) entries

let rec last = function
  | [x] -> x
  | _ :: xs -> last xs
  | [] -> invalid_arg "last"

let expr_of_path start_pos end_pos path =
  match path with
  | [] -> invalid_arg "expr_of_path"
  | head :: tail ->
      List.fold_left
        (fun acc segment -> mk (Proj (acc, segment)) start_pos end_pos)
        (mk (Ident head) start_pos end_pos)
        tail
%}

%parameter <A : Ast.S>

%nonassoc below_RPAREN
%nonassoc RPAREN
%right ARROW
%nonassoc EQEQ
%left PLUS MINUS CONCAT
%left TIMES DIV MOD
%left DOT LPAREN

%start <A.expr> main
%start <A.expr> expr_main

%%

main:
    file_body EOF
        { let (entries, result) = $1 in
          check_file_entries entries result;
          mk (Record (nodes entries)) $startpos $endpos }

expr_main:
    expr EOF { $1 }

expr:
    | NUM                  { mk (Num $1) $startpos $endpos }
    | STRING               { mk (String $1) $startpos $endpos }
    | LABEL                { mk (Label $1) $startpos $endpos }
    | CASE expr LBRACE case_branches RBRACE
        { mk (Case ($2, $4)) $startpos $endpos }
    | LIDENT ARROW expr    { mk (Lambda ([$1], $3)) $startpos $endpos }
    | LPAREN RPAREN ARROW expr { mk (Lambda ([], $4)) $startpos $endpos }
    | LPAREN LIDENT RPAREN ARROW expr { mk (Lambda ([$2], $5)) $startpos $endpos }
    | LPAREN LIDENT COMMA lambda_params_rest RPAREN ARROW expr
        { mk (Lambda ($2 :: $4, $7)) $startpos $endpos }
    (* "(x)" is ambiguous until the token after ")": a lambda's parameter list
       if it is "->", a parenthesised x otherwise. So after "( x" with ")"
       next, x is not reduced to an expression (the %prec below), and "(x)"
       is parsed by its own rule, which yields the same Ident x. *)
    | LPAREN LIDENT RPAREN { mk (Ident $2) $startpos $endpos }
    | LIDENT %prec below_RPAREN { mk (Ident $1) $startpos $endpos }
    | SOME LPAREN type_expr RPAREN { mk (Some_val $3) $startpos $endpos }
    | struct_expr          { $1 }
    | list_expr            { $1 }
    | expr DOT LIDENT      { mk (Proj ($1, $3)) $startpos $endpos }
    | expr LPAREN expr_items RPAREN { mk (Call ($1, $3)) $startpos $endpos }
    | expr EQEQ expr       { mk (Eq ($1, $3)) $startpos $endpos }
    | expr CONCAT expr     { mk (Concat ($1, $3)) $startpos $endpos }
    | expr PLUS expr       { mk (Add ($1, $3)) $startpos $endpos }
    | expr MINUS expr      { mk (Sub ($1, $3)) $startpos $endpos }
    | expr TIMES expr      { mk (Mul ($1, $3)) $startpos $endpos }
    | expr DIV expr        { mk (Div ($1, $3)) $startpos $endpos }
    | expr MOD expr        { mk (Mod ($1, $3)) $startpos $endpos }
    | LPAREN expr RPAREN   { $2 }

(* At least one branch, comma-separated, with an optional trailing comma. *)
case_branches:
    | case_branch { [$1] }
    | case_branch COMMA { [$1] }
    | case_branch COMMA case_branches { $1 :: $3 }

case_branch:
    | pattern ARROW expr { { pattern = $1; body = $3 } }

pattern:
    | LABEL { mk (Label_pattern $1) $startpos $endpos }
    | LBRACE record_pattern_body RBRACE
        { let (fields, is_open) = $2 in
          mk (if is_open then Open_record_pattern fields else Record_pattern fields)
            $startpos $endpos }

(* Field names, comma-separated, optionally ending with "..", which makes the
   pattern open; a trailing comma is allowed when there is no "..". *)
record_pattern_body:
    | { ([], false) }
    | DOTDOT { ([], true) }
    | LIDENT { ([$1], false) }
    | LIDENT COMMA record_pattern_body
        { let (fields, is_open) = $3 in ($1 :: fields, is_open) }

lambda_params_rest:
    | { [] }
    | LIDENT { [$1] }
    | LIDENT COMMA lambda_params_rest { $1 :: $3 }

list_expr:
    | LBRACKET expr_items RBRACKET { mk (List $2) $startpos $endpos }

expr_items:
    | { [] }
    | expr expr_item_rest { $1 :: $2 }

expr_item_rest:
    | { [] }
    | COMMA { [] }
    | COMMA expr expr_item_rest { $2 :: $3 }

(* Whether a brace group is a record or a block is known only at its "}":
   a block is one that ends with a result (spec, section 3.3). *)
struct_expr:
    | LBRACE struct_body RBRACE
        { let (entries, result) = $2 in
          match result with
          | None -> mk (Record (nodes entries)) $startpos $endpos
          | Some (expr, _) ->
              check_block_entries entries;
              mk (Block (nodes entries, expr)) $startpos $endpos }

(* A file is a struct whose entries may also be specs; specs are allowed
   only there (spec, section 7). *)
file_body:
    | entries(file_entry) { $1 }

struct_body:
    | entries(struct_entry) { $1 }

(* Comma-separated entries, with an optional trailing comma, and at most one
   result, which must come last. Returns the entries and the result. *)
entries(entry):
    | { ([], None) }
    | result_entry opt_comma { ([], Some $1) }
    | entry entries_tail(entry) { let (entries, result) = $2 in ($1 :: entries, result) }

entries_tail(entry):
    | { ([], None) }
    | COMMA { ([], None) }
    | COMMA entry entries_tail(entry) { let (entries, result) = $3 in ($2 :: entries, result) }
    | COMMA result_entry opt_comma { ([], Some $2) }

file_entry:
    | nonresult_entry { $1 }
    | SPEC LBRACE spec_body RBRACE
        { (Other_role, diagnostic_position $startpos,
           mk (Spec ($1, $3)) $startpos $endpos) }

(* A spec in a nested struct is parsed, so that the error can say what is
   wrong instead of reporting an unexpected token. *)
struct_entry:
    | nonresult_entry { $1 }
    | SPEC LBRACE spec_body RBRACE
        { error (Diagnostic.Nested_spec {
            title = $1;
            position = diagnostic_position $startpos;
          }) }

(* A spec's body: locals, private types and ensures, comma-separated, with
   an optional trailing comma. *)
spec_body:
    | { [] }
    | spec_entry { [$1] }
    | spec_entry COMMA spec_body { $1 :: $3 }

spec_entry:
    | LIDENT EQUAL expr { mk (Local ($1, $3)) $startpos $endpos }
    | UIDENT type_params EQUAL type_expr
        { mk (Type_local ($1, $2, $4)) $startpos $endpos }
    | ENSURE expr { mk (Ensure $2) $startpos $endpos }

opt_comma:
    | { () }
    | COMMA { () }

nonresult_entry:
    | nonresult_node
        { let (role, node) = $1 in (role, diagnostic_position $startpos, node) }

nonresult_node:
    | LIDENT COLON expr { (Field_role $1, mk (Field ($1, $3)) $startpos $endpos) }
    | LIDENT EQUAL expr { (Other_role, mk (Local ($1, $3)) $startpos $endpos) }
    (* Type entries (spec, section 3.8). *)
    | UIDENT type_params COLON type_expr
        { (Public_type_role $1, mk (Type_field ($1, $2, $4)) $startpos $endpos) }
    | UIDENT type_params EQUAL type_expr
        { (Other_role, mk (Type_local ($1, $2, $4)) $startpos $endpos) }
    (* Allowed in any block (spec, section 7.1). *)
    | ENSURE expr { (Other_role, mk (Ensure $2) $startpos $endpos) }
    | DO expr { (Do_role, mk (Do $2) $startpos $endpos) }
    (* Punning (spec, section 3.2): { x } means { x: x } and { p.name }
       means { name: p.name }; { Bool } and { m.Bool } re-export a type. *)
    | value_path
        { let name = last $1 in
          (Field_role name,
           mk (Field (name, expr_of_path $startpos $endpos $1)) $startpos $endpos) }
    | type_path
        { let (prefix, name) = $1 in
          let rhs = mk (Type_ref (prefix, name)) $startpos $endpos in
          (Public_type_role name, mk (Type_field (name, [], rhs)) $startpos $endpos) }

(* Value names joined by dots. Left-recursive, so that after "a." the next
   token decides between a longer value path and a type path. *)
value_path:
    | LIDENT { [$1] }
    | value_path DOT LIDENT { $1 @ [$3] }

(* A type name, optionally reached through a value path: types are members
   of records, not of other types, so a type name can only come last. *)
type_path:
    | UIDENT { ([], $1) }
    | value_path DOT UIDENT { ($1, $3) }

(* Ordering(A), Result(A, E): the parameters of a type constructor. *)
type_params:
    | { [] }
    | LPAREN type_param_list RPAREN { $2 }

type_param_list:
    | UIDENT { [$1] }
    | UIDENT COMMA { [$1] }
    | UIDENT COMMA type_param_list { $1 :: $3 }

result_entry:
    | RESULT expr { ($2, diagnostic_position $startpos) }

type_expr:
    | type_path
        { let (prefix, name) = $1 in mk (Type_ref (prefix, name)) $startpos $endpos }
    | TYPE_VAR { mk (Type_var $1) $startpos $endpos }
    | type_path LPAREN type_expr_args RPAREN
        { let (prefix, name) = $1 in
          mk (Type_apply (prefix, name, $3)) $startpos $endpos }
    | LBRACE type_record_fields RBRACE { mk (Type_record $2) $startpos $endpos }

type_expr_args:
    | type_expr { [$1] }
    | type_expr COMMA { [$1] }
    | type_expr COMMA type_expr_args { $1 :: $3 }

type_record_fields:
    | { [] }
    | type_record_field_list { $1 }

type_record_field_list:
    | type_record_field { [$1] }
    | type_record_field COMMA { [$1] }
    | type_record_field COMMA type_record_field_list { $1 :: $3 }

type_record_field:
    | LIDENT COLON type_expr { ($1, $3) }
