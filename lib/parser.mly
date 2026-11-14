%{
open A

let mk_loc start_pos end_pos =
  of_lexing_positions start_pos end_pos

let mk node start_pos end_pos =
  with_loc (mk_loc start_pos end_pos) node
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
    struct_body EOF { mk (Struct $1) $startpos $endpos }

expr_main:
    expr EOF { $1 }

expr:
    | NUM                  { mk (Num $1) $startpos $endpos }
    | STRING               { mk (String $1) $startpos $endpos }
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
    | LPAREN expr RPAREN   { $2 }

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

struct_expr:
    | LBRACE struct_body RBRACE { mk (Struct $2) $startpos $endpos }

struct_body:
    | { [] }
    | result_entry opt_comma { [$1] }
    | nonresult_entry nonresult_tail { $1 :: $2 }

nonresult_tail:
    | { [] }
    | COMMA { [] }
    | COMMA nonresult_entry nonresult_tail { $2 :: $3 }
    | COMMA result_entry { [$2] }
    | COMMA result_entry COMMA { [$2] }

opt_comma:
    | { () }
    | COMMA { () }

nonresult_entry:
    | LIDENT COLON expr { mk (Field ($1, $3)) $startpos $endpos }
    | LIDENT EQUAL expr { mk (Local ($1, $3)) $startpos $endpos }

result_entry:
    | RESULT expr { mk (Result $2) $startpos $endpos }

type_expr:
    | UIDENT { mk (Type_ident $1) $startpos $endpos }
    | UIDENT LPAREN type_expr_args RPAREN { mk (Type_apply ($1, $3)) $startpos $endpos }
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
