module Prod_ast = Ast.Located
module Unit_ast = Ast.Unit

module Prod_parser = Parser.Make (Prod_ast)
module Unit_parser = Parser.Make (Unit_ast)

module Make_parse
  (P : sig
    type token
    type main_result
    type expr_result
    module MenhirInterpreter : MenhirLib.IncrementalEngine.INCREMENTAL_ENGINE
      with type token = token
    module Incremental : sig
      val main : Lexing.position -> main_result MenhirInterpreter.checkpoint
      val expr_main : Lexing.position -> expr_result MenhirInterpreter.checkpoint
    end
  end)
  (L : sig
    val token : Lexing.lexbuf -> P.token
  end) =
struct
  let parse_with checkpoint lexbuf =
    let module I = P.MenhirInterpreter in

    let rec loop checkpoint =
      match checkpoint with
      | I.InputNeeded _ ->
          let token = L.token lexbuf in

          let startp = Lexing.lexeme_start_p lexbuf in
          let endp = Lexing.lexeme_end_p lexbuf in

          let checkpoint =
            I.offer checkpoint (token, startp, endp)
          in

          loop checkpoint

      | I.Shifting _
      | I.AboutToReduce _ ->
          loop (I.resume checkpoint)

      | I.HandlingError _ ->
          let pos = Lexing.lexeme_start_p lexbuf in
          let column = pos.pos_cnum - pos.pos_bol + 1 in
          let token = Lexing.lexeme lexbuf in

          let position = {
            Diagnostic.filename = pos.pos_fname;
            line = pos.pos_lnum;
            column;
          } in

          if token = "" then
            raise (Diagnostic.Error (
              Diagnostic.Unexpected_end_of_input { position }
            ))
          else
            raise (Diagnostic.Error (
              Diagnostic.Unexpected_token {
                token;
                position;
              }
            ))

      | I.Accepted ast ->
          ast

      | I.Rejected ->
          failwith "Parser rejected input unexpectedly"
    in

    loop checkpoint

  let parse lexbuf =
    parse_with (P.Incremental.main lexbuf.Lexing.lex_curr_p) lexbuf

  let parse_expr lexbuf =
    parse_with (P.Incremental.expr_main lexbuf.Lexing.lex_curr_p) lexbuf
end

module Prod_parser_instance = struct
  include Prod_parser
  type main_result = Prod_ast.expr
  type expr_result = Prod_ast.expr
end

module Unit_parser_instance = struct
  include Unit_parser
  type main_result = Unit_ast.expr
  type expr_result = Unit_ast.expr
end

module Prod_parse = Make_parse (Prod_parser_instance) (Lexer)
module Unit_parse = Make_parse (Unit_parser_instance) (Lexer)

let parse = Prod_parse.parse
let parse_expr = Prod_parse.parse_expr

let parse_unit = Unit_parse.parse
let parse_expr_unit = Unit_parse.parse_expr
