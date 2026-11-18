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
    val describe : P.token -> string option
    val is_comparison : P.token -> bool
    val keyword_name : P.token -> string option
    val name_token : string -> P.token
    val takes_expression : P.token -> bool
    val ends_entry : P.token -> bool
  end) =
struct
  let parse_with checkpoint lexbuf =
    let module I = P.MenhirInterpreter in

    let rec settle checkpoint =
      match checkpoint with
      | I.Shifting _ | I.AboutToReduce _ -> settle (I.resume checkpoint)
      | _ -> checkpoint
    in

    (* A keyword used as a name, as in "x = do", "{ case = 1 }" or
       "f(some)": read as a name, the keyword would have let the parser
       accept the token after it. That token is the failing one when the
       parser accepted the keyword; otherwise the keyword is the failing
       token and the next one is peeked at, so that "every(Num)" in a
       pattern is not mistaken for a name. Each entry of [history] is a
       token, its positions, and the checkpoint just before it was offered;
       the failing token comes first. *)
    let keyword_as_name history =
      let name_then_accepts (token, startp, endp, before) (next, next_startp) =
        match L.keyword_name token with
        | Some keyword ->
            (match settle (I.offer before (L.name_token keyword, startp, endp)) with
            | I.InputNeeded _ as after when I.acceptable after next next_startp ->
                Some (keyword, startp)
            | _ -> None)
        | None -> None
      in
      let peek () =
        match L.token lexbuf with
        | next -> Some (next, Lexing.lexeme_start_p lexbuf)
        | exception Diagnostic.Error _ -> None
      in
      match history with
      | ((token, _, _, _) as failing) :: _ when L.keyword_name token <> None ->
          Option.bind (peek ()) (name_then_accepts failing)
      | (failing, failing_startp, _, _) :: previous :: _ ->
          name_then_accepts previous (failing, failing_startp)
      | _ -> None
    in

    (* "ensure" or "do" directly followed by the end of an entry. *)
    let missing_expression = function
      | (failing, _, _, _) :: (token, startp, _, _) :: _
        when L.takes_expression token && L.ends_entry failing ->
          Option.map (fun keyword -> (keyword, startp)) (L.keyword_name token)
      | _ -> None
    in

    let rec loop history checkpoint =
      match checkpoint with
      | I.InputNeeded _ ->
          let token = L.token lexbuf in

          let startp = Lexing.lexeme_start_p lexbuf in
          let endp = Lexing.lexeme_end_p lexbuf in

          let history =
            match history with
            | previous :: _ -> [ (token, startp, endp, checkpoint); previous ]
            | [] -> [ (token, startp, endp, checkpoint) ]
          in

          loop history (I.offer checkpoint (token, startp, endp))

      | I.Shifting _
      | I.AboutToReduce _ ->
          loop history (I.resume checkpoint)

      | I.HandlingError _ ->
          (match missing_expression history with
          | Some (keyword, startp) ->
              raise (Diagnostic.Error (
                Diagnostic.Missing_expression { keyword; position = Position.of_lexing startp }
              ))
          | None -> ());

          (match keyword_as_name history with
          | Some (keyword, startp) ->
              raise (Diagnostic.Error (
                Diagnostic.Keyword_as_name { keyword; position = Position.of_lexing startp }
              ))
          | None -> ());

          (* The failing token is the most recent one. *)
          let (description, comparison, pos) =
            match history with
            | (token, startp, _, _) :: _ ->
                (L.describe token, L.is_comparison token, startp)
            | [] -> (None, false, lexbuf.Lexing.lex_curr_p)
          in
          let position = Position.of_lexing pos in

          (match description with
          | Some operator when comparison ->
              raise (Diagnostic.Error (
                Diagnostic.Misplaced_comparison { operator; position }
              ))
          | None ->
              raise (Diagnostic.Error (
                Diagnostic.Unexpected_end_of_input { position }
              ))
          | Some token ->
              raise (Diagnostic.Error (
                Diagnostic.Unexpected_token {
                  token;
                  position;
                }
              )))

      | I.Accepted ast ->
          ast

      | I.Rejected ->
          failwith "Parser rejected input unexpectedly"
    in

    loop [] checkpoint

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
