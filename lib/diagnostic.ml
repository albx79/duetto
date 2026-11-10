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
  | Unterminated_string of {
      position: position;
    }
  | Invalid_escape of {
      sequence: string;
      position: position;
    }
  | Integer_out_of_range of {
      literal: string;
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

  | Unterminated_string { position } ->
      Printf.sprintf "Unterminated string literal starting at %s"
        (string_of_position position)

  | Invalid_escape { sequence; position } ->
      Printf.sprintf "Invalid escape sequence '%s' at %s"
        sequence (string_of_position position)

  | Integer_out_of_range { literal; position } ->
      Printf.sprintf "Integer literal %s is out of range at %s"
        literal (string_of_position position)

  | Unexpected_token { token; position } ->
      Printf.sprintf "Unexpected token '%s' at %s"
        token (string_of_position position)

  | Unexpected_end_of_input { position } ->
      Printf.sprintf "Unexpected end of input at %s"
        (string_of_position position)