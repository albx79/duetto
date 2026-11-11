%{
open Ast
%}

%token <string> NUM
%token <string> STRING
%token <string> LABEL    (* 'name, without the quote *)
%token <string> LIDENT   (* value names *)
%token <string> UIDENT   (* type names *)
%token <string> SPEC     (* spec keyword with its free-text title *)
%token CASE SOME ENSURE
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
%left TIMES DIV

%start <Ast.expr> main

%%

main:
    expr EOF { $1 }

expr:
    | NUM                  { Num $1 }
    | struct_expr          { $1 }
    | expr PLUS expr       { Add ($1, $3) }
    | expr MINUS expr      { Sub ($1, $3) }
    | expr TIMES expr      { Mul ($1, $3) }
    | expr DIV expr        { Div ($1, $3) }
    | LPAREN expr RPAREN   { $2 }

struct_expr:
    | LBRACE struct_fields RBRACE { Struct $2 }

struct_fields:
    | { [] }
    | nonempty_struct_fields { $1 }

nonempty_struct_fields:
    | struct_field                              { [$1] }
    | struct_field COMMA                        { [$1] }
    | struct_field COMMA nonempty_struct_fields { $1 :: $3 }

struct_field:
    | LIDENT COLON field_value { ($1, $3) }

field_value:
    | NUM { Num $1 }
    | struct_expr { $1 }

