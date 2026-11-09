let parse lexbuf =
  let module I = Parser.MenhirInterpreter in

  let checkpoint =
    Parser.Incremental.main lexbuf.Lexing.lex_curr_p
  in

  let rec loop checkpoint =
    match checkpoint with

    | I.InputNeeded _ ->
        let token = Lexer.token lexbuf in

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
