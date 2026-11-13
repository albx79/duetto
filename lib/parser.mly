%{
open Ast
%}

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

%start <Ast.expr> main
%start <Ast.expr> expr_main

%%

main:
    struct_body EOF { Struct $1 }

expr_main:
    expr EOF { $1 }

expr:
    | NUM                  { Num $1 }
    | LIDENT               { Ident $1 }
    | SOME LPAREN type_expr RPAREN { Some_val $3 }
    | struct_expr          { $1 }
    | expr DOT LIDENT      { Proj ($1, $3) }
    | expr PLUS expr       { Add ($1, $3) }
    | expr MINUS expr      { Sub ($1, $3) }
    | expr TIMES expr      { Mul ($1, $3) }
    | expr DIV expr        { Div ($1, $3) }
    | LPAREN expr RPAREN   { $2 }

struct_expr:
    | LBRACE struct_body RBRACE { Struct $2 }

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
    | LIDENT COLON expr { Field ($1, $3) }
    | LIDENT EQUAL expr { Local ($1, $3) }

result_entry:
    | RESULT expr { Result $2 }

type_expr:
    | UIDENT { Type_ident $1 }
    | UIDENT LPAREN type_expr_args RPAREN { Type_apply ($1, $3) }
    | LBRACE type_record_fields RBRACE { Type_record $2 }

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

