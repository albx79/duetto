%{
open Ast
%}

%token <int> INT
%token PLUS
%token TIMES
%token LPAREN
%token RPAREN
%token EOF

%left PLUS
%left TIMES

%start <Ast.expr> main

%%

main:
    expr EOF { $1 }

expr:
    | INT                  { Int $1 }
    | expr PLUS expr       { Add ($1, $3) }
    | expr TIMES expr      { Mul ($1, $3) }
    | LPAREN expr RPAREN   { $2 }

