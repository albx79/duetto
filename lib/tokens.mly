/* The tokens, shared by the lexer and the parser. Menhir generates them as
   the module [Tokens], outside the parser functor, so the lexer does not
   depend on any instance of the parser. */

%token <string> NUM
%token <string> STRING
%token <string> LABEL    (* 'name, without the quote *)
%token <string> LIDENT   (* value names *)
%token <string> UIDENT   (* type names *)
%token <string> TYPE_VAR (* ?Name, the first occurrence of a type variable, without the ? *)
%token <Spec_title.t> SPEC (* spec keyword with its title *)
%token CASE SOME EVERY ENSURE DO DOUBLE
%token ARROW EQEQ RESULT DOTDOT CONCAT
%token LT LE GT GE EQUIV  (* < <= > >= ~~, only after ord ? *)
%token PLUS
%token MINUS
%token TIMES
%token DIV
%token MOD
%token EQUAL COLON COMMA DOT BAR QUESTION CARET
%token LPAREN
%token RPAREN
%token LBRACE RBRACE LBRACKET RBRACKET
%token EOF

%%
