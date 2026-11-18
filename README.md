<p align="center"><img src="duetto.png" alt="Duetto" width="480"></p>

# Duetto

Duetto is an experimental programming language in which **specifications
define interfaces**. A program has two voices: **specs**, which are
executable examples and laws, and **production code**. You do not write
types for your public functions: the compiler extracts each signature from
how the specs use the function, and then checks the implementation against
it. Specs are at the same time the program's tests, and a catalogue of
example values for other specs to reuse.

Duetto is a whole-program language with exact structural records, labels,
struct unions and no type-directed dispatch. The design is in two documents:

- [`SPEC.md`](SPEC.md), the design draft, which covers the whole language;
- [`Duetto Formal Core.md`](Duetto%20Formal%20Core.md), the formal rules for
  the core fragment: typing, signature extraction and checking. Where the two
  overlap, the formal core is authoritative.

## A taste of Duetto

```duetto
# A function, and the spec its type comes from.
greet: person -> "Hello, " ++ person.name,

spec greets people by name {
    ensure greet({ name: "Ada" }) == "Hello, Ada",
    p = some({ name: String, .. }),
    ensure greet(p) == "Hello, " ++ p.name,
},
```

`greet` has no type annotation. The spec calls it with a record, and with
`some(...)`, an arbitrary record that has at least a `name`, so the compiler
extracts the signature `greet : ({ name: String, .. }) -> String`: it takes
any record with a string `name` and returns a string. The spec's `ensure`s
are then run as tests, with `some` generating the values.

## Status

The parser is complete for the syntax in the design draft. The evaluator in
`bin/main.ml` is a toy that runs a few literal expressions, and will be
replaced. The type checker is the next step; see the roadmap below.

## Building and testing

Duetto is written in OCaml, built with dune and Menhir.

### Quick setup with devbox

[devbox](https://www.jetify.com/devbox) provides opam, a C toolchain and the
other tools in an isolated shell, as listed in `devbox.json`:

```sh
devbox shell                      # enter the environment
opam init --bare -n               # once, if opam has never been initialised
opam switch create . --deps-only --with-test -y   # a local switch in _opam/
eval $(opam env)
```

The local switch installs the OCaml compiler and the dependencies declared in
`duetto.opam`, and is ignored by git.

### Without devbox

Install [opam](https://opam.ocaml.org/doc/Install.html), then run the same
`opam switch create` and `eval $(opam env)` commands as above.

### Build, test and run

```sh
dune build                        # build the library and the duetto executable
dune test                         # run the lexer and parser tests
dune exec duetto < file.duetto    # parse a file and run the toy evaluator
```

The tests are in `test/`: `test_lexer.ml` and `test_parser.ml` check tokens,
syntax trees and error messages, and every file under `test/duetto/` must
parse. `test/duetto/accepted-specs.duetto` holds the accepted cases of the
formal core.

### Editor support

`tree-sitter-duetto/` is a [tree-sitter](https://tree-sitter.github.io/)
grammar for syntax highlighting. With the tree-sitter CLI
(`npm install -g tree-sitter-cli`):

```sh
cd tree-sitter-duetto
tree-sitter generate              # after editing grammar.js
tree-sitter test                  # run its test corpus
```

`editors/zed/` is a [Zed](https://zed.dev) extension that uses it. In Zed,
run "zed: install dev extension" and choose `editors/zed`. On Windows, install
it from a Windows folder rather than from inside WSL.

## Roadmap

The type checker follows the formal core, in five steps. The formal core's
test cases, accepted (A, U) and rejected (R), become test files along the
way, so each step makes more of them pass.

1. **Name resolution.** Link every name to its definition, report undefined
   and duplicate names, and expand type aliases.
2. **Typing the core.** Type records, labels, lambdas, `case` on labels, `==`
   and arithmetic, with flexible and rigid type variables and `lacks`
   constraints (formal core, sections 3 to 4).
3. **Usages from specs.** Type each spec and record how it uses each field
   (formal core, section 5).
4. **Extraction.** Turn usages into signatures: one spec supplies each
   signature, with label sets and record fields joined within that spec, and
   every other spec checked for inclusion (formal core, section 6).
5. **Checking.** Check each implementation against its extracted signature,
   and re-check the specs (formal core, section 7).
