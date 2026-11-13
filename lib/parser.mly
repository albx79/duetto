%{
open A

let mk_loc start_pos end_pos =
  of_lexing_positions start_pos end_pos

let mk node start_pos end_pos =
  with_loc (mk_loc start_pos end_pos) node
%}

%parameter <A : Ast.S>

%token <string> NUM
%token <string> STRING
%token <string> LABEL    (* 'name, without the quote *)
%token <string> LIDENT   (* value names *)
%token <string> UIDENT   (* type names *)
%token <string> SPEC     (* spec keyword with its free-text title *)
%token CASE SOME ENSURE DO
%token ARROW EQEQ RESULT DOTDOT CONCAT
%token PLUS
%token MINUS
%token TIMES
%token DIV
%token MOD
%token EQUAL COLON COMMA DOT BAR QUESTION
%token LPAREN
%token RPAREN
%token LBRACE RBRACE LBRACKET RBRACKET
%token EOF

%left PLUS MINUS
%left TIMES DIV MOD
%left DOT

%start <A.expr> main
%start <A.expr> expr_main

%%

main:
    struct_body EOF { mk (Struct $1) $startpos $endpos }

expr_main:
    expr EOF { $1 }

expr:
    | NUM                  { mk (Num $1) $startpos $endpos }
    | LIDENT               { mk (Ident $1) $startpos $endpos }
    | SOME LPAREN type_expr RPAREN { mk (Some_val $3) $startpos $endpos }
    | struct_expr          { $1 }
    | list_expr            { $1 }
    | expr DOT LIDENT      { mk (Proj ($1, $3)) $startpos $endpos }
    | expr PLUS expr       { mk (Add ($1, $3)) $startpos $endpos }
    | expr MINUS expr      { mk (Sub ($1, $3)) $startpos $endpos }
    | expr TIMES expr      { mk (Mul ($1, $3)) $startpos $endpos }
    | expr DIV expr        { mk (Div ($1, $3)) $startpos $endpos }
    | LPAREN expr RPAREN   { $2 }

list_expr:
    | LBRACKET list_items RBRACKET { mk (List $2) $startpos $endpos }

list_items:
    | { [] }
    | expr list_item_rest { $1 :: $2 }

list_item_rest:
    | { [] }
    | COMMA { [] }
    | COMMA expr list_item_rest { $2 :: $3 }

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
