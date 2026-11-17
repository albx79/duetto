/**
 * @file Tree-sitter grammar for Duetto
 *
 * Follows the reference parser, lib/parser.mly, and the design draft,
 * SPEC.md. Like any tree-sitter grammar it is more permissive than the
 * reference parser: checks that need the whole brace group, such as
 * "a block has no fields" (spec, section 3.2), are left to the compiler.
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

// Higher binds tighter. The comparison under an ordering, ord ? a < b, is at
// the level of ==; its ordering binds tighter than arithmetic (spec, 6.2).
const PREC = {
  lambda: 1,
  compare: 2,
  add: 3,
  mul: 4,
  ordering: 5,
  postfix: 6,
};

// In types, | binds tighter than ->: (A) -> B | C is (A) -> (B | C).
const TYPE_PREC = {
  function: 1,
  union: 2,
};

/** Comma-separated, with an optional trailing comma. */
function commaSep(rule) {
  return optional(commaSep1(rule));
}

function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)), optional(','));
}

module.exports = grammar({
  name: 'duetto',

  extras: $ => [/\s/, $.comment],

  word: $ => $.identifier,

  conflicts: $ => [
    // (x) is a parenthesised expression or a lambda's parameter list, and
    // only the token after ")" decides (spec, section 3.4).
    [$._expression, $.parameters],
    // An entry m.x is a punned field, m.T a punned type: the last name
    // decides.
    [$.value_path, $.type_path],
  ],

  rules: {
    // A file is a static struct: its entries, without braces (spec, 3.2).
    source_file: $ => commaSep($._entry),

    _entry: $ => choice(
      $.field,
      $.local,
      $.type_field,
      $.type_local,
      $.ensure,
      $.do,
      $.result,
      $.punned_field,
      $.punned_type,
      $.spec,
    ),

    field: $ => seq(
      field('name', $.identifier), ':', field('value', $._expression)),

    local: $ => seq(
      field('name', $.identifier), '=', field('value', $._expression)),

    type_field: $ => seq(
      field('name', $.type_identifier),
      optional(field('parameters', $.type_parameters)),
      ':',
      field('type', $._type)),

    type_local: $ => seq(
      field('name', $.type_identifier),
      optional(field('parameters', $.type_parameters)),
      '=',
      field('type', $._type)),

    type_parameters: $ => seq('(', commaSep1($.type_identifier), ')'),

    ensure: $ => seq('ensure', field('condition', $._expression)),

    do: $ => seq('do', field('effect', $._expression)),

    result: $ => seq('<<', field('value', $._expression)),

    // { x } means { x: x }, and { p.name } means { name: p.name }.
    punned_field: $ => $.value_path,

    // { Bool } and { m.Bool } re-export a type.
    punned_type: $ => $.type_path,

    value_path: $ => seq(
      $.identifier, repeat(seq('.', $.identifier))),

    // Specs (spec, sections 3.6, 7 and 10.9).
    spec: $ => seq(
      'spec',
      field('title', $.spec_title),
      field('body', $.spec_body)),

    // Free text up to "{", with interface names marked in backticks.
    spec_title: $ => repeat1(choice($.title_text, $.title_mark)),

    title_text: _ => token(prec(-1, /[^{}`\s][^{}`]*/)),

    title_mark: $ => seq(
      '`',
      repeat(seq(field('path', $.identifier), '.')),
      field('name', $.type_identifier),
      '`'),

    spec_body: $ => seq('{', commaSep($._entry), '}'),

    // Expressions.

    _expression: $ => choice(
      $.number,
      $.string,
      $.label,
      $.identifier,
      $.parenthesized_expression,
      $.list,
      $.struct,
      $.case,
      $.double,
      $.some,
      $.every,
      $.lambda,
      $.binary_expression,
      $.comparison,
      $.call,
      $.projection,
    ),

    parenthesized_expression: $ => seq('(', $._expression, ')'),

    list: $ => seq('[', commaSep($._expression), ']'),

    // A record, or a block if it ends with << (spec, section 3.3).
    struct: $ => seq('{', commaSep($._entry), '}'),

    lambda: $ => prec.right(PREC.lambda, seq(
      field('parameters', choice($.identifier, $.parameters)),
      '->',
      field('body', $._expression))),

    parameters: $ => seq('(', commaSep($.identifier), ')'),

    binary_expression: $ => choice(
      prec.left(PREC.compare, seq(
        field('left', $._expression),
        field('operator', '=='),
        field('right', $._expression))),
      ...[['++', PREC.add], ['+', PREC.add], ['-', PREC.add],
          ['*', PREC.mul], ['/', PREC.mul], ['%', PREC.mul]]
        .map(([operator, precedence]) => prec.left(precedence, seq(
          field('left', $._expression),
          field('operator', operator),
          field('right', $._expression)))),
    ),

    // ord ? a < b (spec, section 6.2).
    comparison: $ => prec.left(PREC.compare, seq(
      field('ordering', $._ordering),
      '?',
      field('left', $._expression),
      field('operator', choice('<', '<=', '>', '>=', '~~')),
      field('right', $._expression))),

    _ordering: $ => prec(PREC.ordering, choice(
      $.identifier,
      $.projection,
      $.call,
      $.parenthesized_expression,
    )),

    call: $ => prec(PREC.postfix, seq(
      field('function', $._expression),
      field('arguments', $.arguments))),

    arguments: $ => seq('(', commaSep($._expression), ')'),

    projection: $ => prec(PREC.postfix, seq(
      field('record', $._expression),
      '.',
      field('field', $.identifier))),

    some: $ => seq('some', '(', field('type', $._type), ')'),

    every: $ => seq('every', '(', field('type', $._type), ')'),

    case: $ => seq(
      'case',
      field('value', $._expression),
      '{',
      commaSep1($.case_branch),
      '}'),

    case_branch: $ => seq(
      field('pattern', $._pattern), '->', field('body', $._expression)),

    // Doubles (spec, section 11).
    double: $ => seq('double', '{', commaSep1($.stub), '}'),

    stub: $ => seq(
      field('name', $.identifier),
      '(',
      commaSep(field('argument', $._pattern)),
      ')',
      repeat1(seq('<<', field('response', $._expression)))),

    // Patterns (spec, section 9).

    _pattern: $ => choice(
      $.label,
      $.number,
      $.string,
      $.identifier,
      $.pinned,
      $.some_pattern,
      $.record_pattern,
    ),

    pinned: $ => seq('^', field('name', $.identifier)),

    some_pattern: $ => seq('some', '(', field('type', $._type), ')'),

    record_pattern: $ => seq(
      '{',
      optional(choice(
        seq(
          $.field_pattern,
          repeat(seq(',', $.field_pattern)),
          optional(seq(',', optional($.rest)))),
        $.rest,
      )),
      '}'),

    field_pattern: $ => choice(
      seq(field('name', $.identifier), ':', field('pattern', $._pattern)),
      field('name', $.identifier)),

    rest: _ => '..',

    // Types (spec, section 4).

    _type: $ => choice(
      $.type_path,
      $.type_application,
      $.type_variable,
      $.label,
      $.record_type,
      $.list_type,
      $.function_type,
      $.union_type,
      $.parenthesized_type,
    ),

    type_path: $ => seq(
      repeat(seq(field('path', $.identifier), '.')),
      field('name', $.type_identifier)),

    type_application: $ => seq(
      field('constructor', $.type_path),
      '(',
      commaSep1($._type),
      ')'),

    type_variable: _ => /\?[A-Z][a-zA-Z0-9]*/,

    record_type: $ => seq(
      '{',
      optional(choice(
        seq(
          $.field_type,
          repeat(seq(',', $.field_type)),
          optional(seq(',', optional($.row)))),
        $.row,
      )),
      '}'),

    field_type: $ => seq(
      field('name', $.identifier), ':', field('type', $._type)),

    row: $ => seq('..', optional(choice($.type_variable, $.type_identifier))),

    list_type: $ => seq('[', $._type, ']'),

    function_type: $ => prec.right(TYPE_PREC.function, seq(
      field('parameters', $.type_parameters_list),
      '->',
      field('result', $._type))),

    type_parameters_list: $ => seq('(', commaSep($._type), ')'),

    union_type: $ => prec.left(TYPE_PREC.union, seq($._type, '|', $._type)),

    parenthesized_type: $ => seq('(', $._type, ')'),

    // Tokens (spec, section 3).

    identifier: _ => /[a-z_][a-z0-9_]*/,

    type_identifier: _ => /[A-Z][a-zA-Z0-9]*/,

    label: _ => /'[a-z_][a-z0-9_]*/,

    number: _ => /\d+(\.\d+)?([eE][+-]?\d+)?/,

    string: $ => seq(
      '"',
      repeat(choice($.string_content, $.escape_sequence)),
      token.immediate('"')),

    string_content: _ => token.immediate(prec(1, /[^"\\]+/)),

    escape_sequence: _ => token.immediate(/\\["\\nt]/),

    comment: _ => token(seq('#', /.*/)),
  },
});
