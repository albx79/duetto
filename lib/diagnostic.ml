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

  | Unexpected_token of {
      token: string;
      position: position;
    }
  | Unexpected_end_of_input of {
      position: position;
    }
  | Misplaced_comparison of {
      operator: string;
      position: position;
    }
  | Reserved_token of {
      token: string;
      position: position;
    }
  | Invalid_spec_title_character of {
      character: string;
      position: position;
    }
  | Missing_spec_title of {
      position: position;
    }
  | Unclosed_title_mark of {
      position: position;
    }
  | Invalid_title_mark of {
      text: string;
      position: position;
    }
  | Nested_spec of {
      title: string;
      position: position;
    }
  | Field_in_block of {
      name: string;
      is_type: bool;
      position: position;
    }
  | Result_in_file of {
      position: position;
    }
  | Tuple_type of {
      position: position;
    }
  | Do_in_file of {
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


  | Unexpected_token { token; position } ->
      Printf.sprintf "Unexpected token '%s' at %s"
        token (string_of_position position)

  | Misplaced_comparison { operator; position } ->
      Printf.sprintf
        "Unexpected '%s' at %s: a comparison names its ordering, as in 'ord ? a %s b', and comparisons cannot be chained"
        operator (string_of_position position) operator

  | Unexpected_end_of_input { position } ->
      Printf.sprintf "Unexpected end of input at %s"
        (string_of_position position)

  | Reserved_token { token; position } ->
      Printf.sprintf "The token '%s' at %s is reserved for future use"
        token (string_of_position position)

  | Invalid_spec_title_character { character = "}"; position } ->
      Printf.sprintf
        "A spec title cannot contain '}', at %s (is the '{' after the title missing?)"
        (string_of_position position)

  | Invalid_spec_title_character { character; position } ->
      Printf.sprintf "A spec title cannot contain '%s', at %s"
        character (string_of_position position)

  | Unclosed_title_mark { position } ->
      Printf.sprintf "The '`' at %s in a spec title is not closed"
        (string_of_position position)

  | Invalid_title_mark { text; position } ->
      Printf.sprintf
        "The mark `%s` at %s is not an interface name: a mark is a type name, such as `Ordering` or `m.Ordering`"
        text (string_of_position position)

  | Nested_spec { title; position } ->
      Printf.sprintf
        "The spec '%s' at %s is inside a nested struct; specs are allowed only at file level"
        title (string_of_position position)

  | Field_in_block { name; is_type = false; position } ->
      Printf.sprintf
        "The field '%s' at %s is in a block: a brace group that ends with '<<' cannot have fields (use '%s = ...' for a local)"
        name (string_of_position position) name

  | Field_in_block { name; is_type = true; position } ->
      Printf.sprintf
        "The public type '%s' at %s is in a block: a brace group that ends with '<<' cannot have public types (use '%s = ...' for a private type)"
        name (string_of_position position) name

  | Tuple_type { position } ->
      Printf.sprintf
        "The parenthesised types at %s are not followed by '->': Duetto has no tuple types"
        (string_of_position position)

  | Result_in_file { position } ->
      Printf.sprintf
        "The '<<' at %s is at file level: a file is a static struct and has no result"
        (string_of_position position)

  | Do_in_file { position } ->
      Printf.sprintf
        "The 'do' at %s is at file level: a file is a static struct and performs no actions"
        (string_of_position position)

  | Missing_spec_title { position } ->
      Printf.sprintf "The spec at %s has no title"
        (string_of_position position)

