%{
open Ast
%}

%token <int> INT
%token PLUS
%token MINUS
%token TIMES
%token DIV
%token LPAREN
%token RPAREN
%token EOF

%left PLUS MINUS
%left TIMES DIV

%start <Ast.expr> main

%%

main:
    expr EOF { $1 }

expr:
    | INT                  { Int $1 }
    | expr PLUS expr       { Add ($1, $3) }
    | expr MINUS expr       { Sub ($1, $3) }
    | expr TIMES expr      { Mul ($1, $3) }
    | expr DIV expr      { Div ($1, $3) }
    | LPAREN expr RPAREN   { $2 }

