type position = {
  filename: string;
  line: int;
  column: int;
}

type error =
  | Unexpected_character of {
      character: string;
      position: position;
    }
  | Unexpected_token of {
      token: string;
      position: position;
    }
  | Unexpected_end_of_input of {
      position: position;
    }

exception Error of error

let string_of_position pos =
  Printf.sprintf "%s:%d:%d"
    pos.filename
    pos.line
    pos.column

let string_of_error = function
  | Unexpected_character { character; position } ->
      Printf.sprintf "Unexpected character '%s' at %s"
        character (string_of_position position)

  | Unexpected_token { token; position } ->
      Printf.sprintf "Unexpected token '%s' at %s"
        token (string_of_position position)

  | Unexpected_end_of_input { position } ->
      Printf.sprintf "Unexpected end of input at %s"
        (string_of_position position)