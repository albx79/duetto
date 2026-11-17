; Highlighting for Duetto. The patterns do not overlap, so their order does
; not matter to editors that disagree on which match wins.

(comment) @comment

(string) @string
(escape_sequence) @string.escape
(number) @number

; Labels are atoms, like symbols in other languages.
(label) @string.special.symbol

[
  "case"
  "some"
  "every"
  "ensure"
  "do"
  "double"
  "spec"
] @keyword

; Spec titles are prose; the interfaces a law spec marks are names.
(title_text) @string.special
(title_mark name: (type_identifier) @type)
(title_mark path: (identifier) @module)
(title_mark "`" @punctuation.special)

; Types.
(type_identifier) @type
(type_variable) @type
(type_path path: (identifier) @module)

; Fields and record members.
(field name: (identifier) @property)
(field_type name: (identifier) @property)
(field_pattern name: (identifier) @property)
(projection field: (identifier) @property)
(punned_field (value_path (identifier) @property))

; Names.
(local name: (identifier) @variable)
(lambda parameters: (identifier) @variable.parameter)
(parameters (identifier) @variable.parameter)
(case_branch pattern: (identifier) @variable)
(stub argument: (identifier) @variable)
(pinned name: (identifier) @variable)

; Calls, and the functions a double stubs.
(call function: (identifier) @function)
(stub name: (identifier) @function)

[
  "+" "-" "*" "/" "%" "++" "=="
  "<" "<=" ">" ">=" "~~" "?"
  "->" "<<" "|" "^" "="
] @operator

[".." (rest)] @punctuation.special

["," ":" "."] @punctuation.delimiter

["(" ")" "[" "]" "{" "}"] @punctuation.bracket
