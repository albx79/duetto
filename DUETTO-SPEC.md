# Duetto Language Draft Specification

## 1. Overview

Duetto is a programming language with two tightly integrated sublanguages:

- **spec**, used to define executable specifications and tests
- **prod**, used to define production code

A Duetto program is a single whole program containing both kinds of code. Any top-level block introduced with `spec` belongs to the spec sublanguage. Any other top-level definition belongs to the production sublanguage.

The central design principle of Duetto is:

> Production code receives its public type information from specifications.

A programmer must write specs before or alongside implementation. Specs are used for:

1. **type extraction**: inferring public function signatures and other interface information
2. **test execution**: checking runtime behavior
3. **recipe extraction**: cataloguing how values of interesting types can be constructed for reuse in other tests

Thus, specs are not only tests: they are also the source of the static interface against which production code is checked.

Duetto source files use the extension:

- `.duetto`

---

## 2. Design goals

Duetto is designed around the following goals:

1. **Specs define interfaces**
   - Public production signatures are inferred from spec usage, not from production implementations.

2. **Shape and behavior live together**
   - A spec simultaneously describes what values a function consumes/produces and what behavior it must satisfy.

3. **Explicit authority**
   - Access to resources such as filesystems and networks is modeled by explicit values passed to functions, not by ambient global powers.

4. **Whole-program spec reuse**
   - If a spec constructs a value of some interface type, that construction can be catalogued and reused by other specs.

5. **Effect-free deterministic specs**
   - Specs are pure, deterministic, and suitable for whole-program analysis and replay.

6. **Minimal core language**
   - The first version avoids advanced mechanisms unless they are necessary for the core model.

---

## 3. Surface structure

A Duetto program consists of a sequence of top-level items:

- type aliases
- production definitions
- spec blocks

Example:

```duetto
type Bool = 'true | 'false

answer() = 42
;;

spec the answer is 42:
  x = answer()
  ensure x == 42
;;
```

---

## 4. Top-level grammar sketch

This section is descriptive rather than fully formal.

```text
Program ::= TopItem*

TopItem ::= TypeAlias
          | Definition
          | SpecBlock
```

### 4.1 Type aliases

```text
TypeAlias ::= type TypeName TypeParams? = TypeExpr
```

Examples:

```duetto
type Bool = 'true | 'false
type OrderingResult = 'lt | 'eq | 'gt
type Ordering(A) = { compare: (A, A) -> OrderingResult }
```

### 4.2 Production definitions

```text
Definition ::= Name "(" ParamList? ")" "=" Expr
               ";;"
```

Examples:

```duetto
answer() = 42
;;

greet(person) = "Hello, " + person.name
;;
```

### 4.3 Spec blocks

```text
SpecBlock ::= spec SpecTitle ":" Newline
              SpecStmt*
              ";;"
```

The title is part of the grammar, not a string literal. It may contain letters, digits, spaces, and selected punctuation up to the terminating `:` followed by newline.

Example:

```duetto
spec greeting works:
  x = greet({ name: "Ada" })
  ensure x == "Hello, Ada"
;;
```

---

## 5. Types

### 5.1 Core type forms

The current draft includes the following type forms:

- `Int`
- `String`
- label singleton types such as `'true`, `'false`, `'lt`
- list types `[T]`
- record types `{ field1: T1, ..., fieldN: TN }`
- function types `(T1, ..., Tn) -> R`
- union types `T | U`
- named type aliases `Name(...)`

Example:

```duetto
type Bool = 'true | 'false
type OrderingResult = 'lt | 'eq | 'gt
type Ordering(A) = { compare: (A, A) -> OrderingResult }
```

### 5.2 Labels instead of Bool

Duetto does not require a primitive `Bool` type.

Instead, labels are primitive atomic values and singleton types. For example:

- `'true`
- `'false`
- `'lt`
- `'eq`
- `'gt`

Boolean-like types can be defined as unions of labels:

```duetto
type Bool = 'true | 'false
```

This is strictly more general than a dedicated boolean primitive.

### 5.3 Lists

Lists are primitive.

- In type position: `[T]`
- In value position: `[x, y, z]`

Examples:

```duetto
type Names = [String]
```

```duetto
["Ada", "Grace", "Linus"]
```

Deconstruction and pattern matching are intentionally not part of v1.

### 5.4 Empty record and zero-argument functions

Duetto has no separate primitive `Unit` type.

Instead, the empty record `{}` serves that role semantically.

- A zero-argument function is treated as a function from `{}`
- A call with no arguments is treated as passing `{}`

Thus:

```duetto
answer() = 42
;;
```

is semantically equivalent to a function of type:

```text
{} -> Int
```

and:

```duetto
answer()
```

is semantically equivalent to:

```duetto
answer({})
```

The syntax `()` is permitted as surface sugar in call/definition syntax for the unique empty record value.

---

## 6. Production language

Everything outside `spec` blocks belongs to the production language.

Production definitions do not require explicit type annotations. However, their public signatures are not inferred from implementation bodies alone. Instead, they are checked against interfaces extracted from specs.

Example:

```duetto
greet(person) = "Hello, " + person.name
;;
```

If specs establish that `greet` is used as:

```text
{ name: String } -> String
```

then the implementation is checked against that signature.

Production code may use local inference internally, but public exported shape is fixed by specs.

---

## 7. Spec language

A spec block contains statements executed in order.

### 7.1 Spec statements

Minimal v1 forms:

```text
SpecStmt ::= Name "=" Expr
           | ensure Expr
```

Examples:

```duetto
spec the answer is 42:
  x = answer()
  ensure x == 42
;;
```

```duetto
spec greeting works:
  person = { name: "Ada" }
  result = greet(person)
  ensure result == "Hello, Ada"
;;
```

### 7.2 Meaning of `ensure`

`ensure` introduces a behavioral obligation.

Examples:

```duetto
ensure x == 42
ensure ord.compare(a, b) == 'lt
ensure is_sorted(xs, ord)
```

An `ensure` expression must evaluate to a boolean-like condition according to the assertion system of the language. In early drafts this may be represented by a `Bool` alias such as `'true | 'false`, or by a dedicated assertion judgment at spec-execution time.

The important semantic point is:

- `ensure` is for executable behavioral checking
- it may also constrain types indirectly through the expressions it contains
- it is not merely a shape-only assertion

### 7.3 Effect-free deterministic specs

Specs are intended to be pure and deterministic.

They do not perform ambient I/O directly. Instead, any interaction with resources is mediated through explicit values, including scripted doubles introduced in the spec itself.

This restriction enables:

- whole-program analysis
- reproducible execution
- extraction of reusable construction recipes

---

## 8. The `some(...)` construct

### 8.1 Purpose

`some(T)` is used only in specs.

It denotes a generated value of type `T`.

Examples:

```duetto
x = some(Int)
name = some(String)
xs = some([Int])
ord = some(Ordering(Int))
```

### 8.2 Type variables

If an uppercase identifier appears in type position inside a spec and is otherwise unbound, it introduces a fresh type variable.

Example:

```duetto
spec identity returns its input:
  x = some(A)
  y = identity(x)
  ensure y == x
;;
```

This contributes the polymorphic interface:

```text
identity : (A) -> A
```

generalized universally over `A`.

Thus `some(A)` means:

- choose an arbitrary value of some abstract type `A`
- statically, require that the implementation works uniformly for that `A`
- dynamically, generate test values for that abstract type according to the generator system

### 8.3 Static meaning

At spec elaboration time, `some(T)` contributes type information.

It is the main bridge between testing and polymorphism.

For example:

```duetto
spec reverse twice is identity:
  xs = some([A])
  ys = reverse(reverse(xs))
  ensure ys == xs
;;
```

contributes polymorphism over `A`.

### 8.4 Dynamic meaning

At test execution time, `some(T)` produces concrete values of type `T` using the test generation system.

This generation must be deterministic with respect to the test runner’s semantics and reproducible enough for replay and debugging.

---

## 9. Structural typing

Duetto uses structural typing for records.

If a function is specified using a record with a given set of fields, the function is checked against that structure, not against a nominal type declaration.

Example:

```duetto
spec greeting works:
  x = greet({ name: "Ada" })
  ensure x == "Hello, Ada"
;;
```

This contributes the input shape:

```text
{ name: String }
```

and return type:

```text
String
```

Thus the inferred public interface is:

```text
greet : ({ name: String }) -> String
```

---

## 10. Explicit interfaces as ordinary values

Duetto does not require dedicated language concepts for typeclasses or capabilities in v1.

Instead, interfaces are represented as ordinary explicit values with structural record types.

Example:

```duetto
type OrderingResult = 'lt | 'eq | 'gt
type Ordering(A) = { compare: (A, A) -> OrderingResult }
```

A sorting function then takes an ordering explicitly:

```duetto
sort_by(xs, ord) = ...
;;
```

rather than relying on implicit instance lookup.

This is intentional:

- it avoids introducing a separate typeclass mechanism
- it keeps authority and behavior explicit
- it works naturally with structural typing and spec-derived generation

Similarly, resource access such as filesystem or network access is represented by ordinary records of functions passed explicitly.

Example:

```duetto
type Reader = { read_text: (String) -> String }
```

Whether such a record represents authority is a property of the surrounding runtime model, not a special type-system marker.

---

## 11. Behavior versus shape

The shape of a value and its behavior are distinct.

For example, a value of type:

```duetto
type Ordering(A) = { compare: (A, A) -> OrderingResult }
```

has the correct interface shape for an ordering, but that does not imply it satisfies laws such as transitivity.

Duetto keeps these concerns together in specs:

- shape is extracted from the types of values used in specs
- behavior is checked by executable assertions in those same specs

This is one of the core ideas of the language: interface shape and behavioral obligations are written in the same place, while remaining conceptually distinct.

---

## 12. Reusable law specs and whole-program checking

A Duetto program is compiled and tested as a whole.

This allows generic specs to be reused over concrete implementations discovered through other specs.

For example, the standard library may define reusable specs expressing ordering laws:

- reflexivity
- sign symmetry
- transitivity

A user may define a function or factory that produces an `Ordering(Foo)` value. Because that function must itself have specs, the compiler/test runner can extract a recipe for constructing such an ordering.

That recipe can then be reused to instantiate the generic ordering-law specs against the user’s implementation.

This leads to an important property:

> If a program introduces a new implementation of an interface and provides specs constructing it, then generic law specs for that interface can automatically be applied to it during whole-program testing.

This is not the same as proving the laws statically. It is whole-program reusable conformance testing driven by spec extraction.

---

## 13. Spec-derived recipes

Each spec has three possible outputs:

1. **type constraints**
   - used to infer public interfaces of production definitions

2. **runtime tests**
   - executed to check behavioral obligations

3. **construction recipes**
   - catalogued descriptions of how values of particular types can be built from deterministic spec code

A construction recipe is extracted from spec code that constructs a value of some type `T` in a deterministic way.

Example sketch:

```duetto
spec config file yields ordering:
  fs = ...
  ord = load_ordering(fs, "config.txt")
  ensure ord.compare(foo1, foo2) == 'lt
;;
```

This may yield a reusable recipe for constructing a value of type `Ordering(Foo)`.

Other specs, including generic law specs, may reuse such recipes to obtain values of the required type.

### 13.1 Coverage model

Spec-derived recipes provide coverage over all construction scenarios described by specs.

They do not automatically cover every value that production code could possibly construct unless those construction paths are themselves described by specs.

Coverage expands as specs become more generative.

---

## 14. Scripted doubles

To support test-first development involving external interactions, Duetto requires a core mechanism for controlled doubles.

This is a language feature, not merely a library convenience, because tests must be writable before arbitrary helper frameworks exist.

The exact surface syntax for doubles is not yet fixed in this draft. However, the intended semantics are:

- a spec can construct an explicit test value standing in for a dependency
- the double has an ordinary structural type, typically a record of functions
- the spec scripts expected interactions and responses
- unexpected interactions fail the test
- missing required interactions fail the test

Example, in hypothetical future syntax:

```duetto
spec loading settings works:
  fs = double:
    read_text("settings.json") returns "{ theme: \"dark\" }"
  ;;

  settings = load_settings(fs, "settings.json")
  ensure settings.theme == "dark"
;;
```

Statically, such a double contributes type information like:

```text
{ read_text: (String) -> String }
```

Dynamically, it enforces the scripted behavior.

The exact notation is deferred, but the concept is part of the language model.

---

## 15. Type extraction model

Type extraction in Duetto is constraint-based over spec bodies.

A spec does not have to be written in a special `example f(...) => ...` form. Instead:

- each binding in a spec has an inferred type
- each production call contributes constraints on argument and result types
- each `ensure` may further constrain expression types

Example:

```duetto
spec the answer is 42:
  x = answer()
  ensure x == 42
;;
```

This implies:

- `answer()` returns `Int`
- therefore `answer : ({}) -> Int`

Similarly:

```duetto
spec greeting works:
  p = { name: "Ada" }
  x = greet(p)
  ensure x == "Hello, Ada"
;;
```

implies:

- `greet` consumes `{ name: String }`
- `greet` produces `String`

thus:

```text
greet : ({ name: String }) -> String
```

### 15.1 Polymorphic extraction

If a spec introduces fresh type variables through `some(A)`, public signatures may be universally generalized over those variables.

Example:

```duetto
spec identity returns its input:
  x = some(A)
  y = identity(x)
  ensure y == x
;;
```

This contributes the polymorphic interface:

```text
identity : (A) -> A
```

with universal quantification over `A`.

---

## 16. Production checking model

Once all spec blocks are analyzed, the compiler derives a public interface environment for production definitions.

Production definitions are then checked against that environment.

Thus:

1. specs are collected and elaborated
2. public signatures are extracted
3. production definitions are typechecked against those signatures
4. specs are executed as tests
5. spec-derived recipes are made available for reusable test instantiation

A production implementation cannot silently strengthen its required input shape or change its return type beyond what the specs establish.

---

## 17. What v1 intentionally does not settle

The following areas are intentionally deferred or only partially specified in this draft:

- exact formal subtyping rules
- full semantics of union types
- variance rules for function types
- recursive user-defined types
- mutable state
- pattern matching and deconstruction
- exact syntax and semantics of scripted doubles
- exact generator semantics for all forms of `some(T)`
- interaction between arbitrary generation and recipe-catalog reuse
- module system and visibility
- exhaustive formal grammar
- operational semantics of all expressions

These are important, but they are not required to state the core idea of Duetto.

---

## 18. Current v1 philosophy

The current Duetto v1 direction can be summarized as follows:

- **Specs are mandatory and first-class**
- **Public production types come from specs**
- **Structural typing is used for ordinary values and interfaces**
- **Labels replace primitive booleans**
- **Lists are primitive and written `[T]` / `[x, y, z]`**
- **The empty record `{}` serves as semantic unit**
- **Interfaces such as orderings and resource handles are ordinary explicit values**
- **Specs are executable behavior checks and sources of type information**
- **Specs can also provide reusable construction recipes**
- **Whole-program testing can automatically apply reusable law specs to spec-constructed implementations**

This is the defining idea of Duetto.

---

## 19. Illustrative examples

### 19.1 Simple constant

```duetto
answer() = 42
;;

spec the answer is 42:
  x = answer()
  ensure x == 42
;;
```

### 19.2 Structural input

```duetto
greet(person) = "Hello, " + person.name
;;

spec greeting works:
  x = greet({ name: "Ada" })
  ensure x == "Hello, Ada"
;;
```

This implies a public interface equivalent to:

```text
greet : ({ name: String }) -> String
```

### 19.3 Polymorphic identity

```duetto
identity(x) = x
;;

spec identity returns its input:
  x = some(A)
  y = identity(x)
  ensure y == x
;;
```

This implies a public interface equivalent to:

```text
identity : (A) -> A
```

### 19.4 Explicit ordering

```duetto
type OrderingResult = 'lt | 'eq | 'gt
type Ordering(A) = { compare: (A, A) -> OrderingResult }

spec ordering compare is reflexive:
  ord = some(Ordering(A))
  x = some(A)
  ensure ord.compare(x, x) == 'eq
;;
```

### 19.5 Sorting with explicit ordering

```duetto
sort_by(xs, ord) = ...
;;

spec sorting preserves length:
  xs = some([Int])
  ord = some(Ordering(Int))
  ys = sort_by(xs, ord)
  ensure length(ys) == length(xs)
;;
```

---

## 20. Summary

Duetto is a whole-program language where specifications are not separate metadata or optional tests. They are executable code that defines:

- what production code is allowed to consume and produce
- what it must do
- how values can be constructed for further conformance testing

The language’s identity is built around this duet between spec and production code.

That is why the language is called **Duetto**.