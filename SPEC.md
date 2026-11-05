# Duetto Language Draft Specification

Oct 18, 2026 · @Alb

## 1. Overview

Duetto is a whole-program language with two tightly integrated sublanguages: **spec**, for executable specifications and tests, and **prod**, for production code. Any top-level block introduced with `spec` belongs to the spec sublanguage; every other top-level definition belongs to prod. Source files use the extension `.duetto`.

The central design principle:

> Production code receives its public type information from specifications.

Specs serve three purposes at once:

1. **Type extraction**: inferring public function signatures from how specs use production code.
2. **Test execution**: checking runtime behavior.
3. **Recipe extraction**: cataloguing how values of interesting types are constructed, for reuse in other specs.

### 1.1 Changes in this revision

- Records are **exact** by default; width subtyping is removed. Openness is opt-in via row polymorphism: `{ f: T, .. }` and `{ f: T, ..R }`.
- Unions are restricted to **unions of labels**, eliminated by an exhaustive label `case`. There are no tagged constructors.
- **No type-directed dispatch.** Closures remain the only form of dynamic dispatch.
- `==` is a **built-in, total, non-overridable** construct. Functions compare by definition site plus captured values.
- Failure is modeled as a **capability** introduced by `try` and defined by `handle` clauses, with exact record payloads per error kind.
- The **`$` sigil** marks second-class (non-escaping) values, enforced statically.
- `some(T)` synthesizes only **function-free** values; function-carrying values come from a **recipe catalogue** built in rounds from passing specs.
- **Law specs** mark interfaces in backticks in their titles and bind each with exactly one `every(...)`.
- Double expectations are explicit `ensure`s over **`calls`**, which only reaches doubles primed in the current spec.

## 2. Design goals

1. **Specs define interfaces.** Public production signatures are inferred from spec usage, not from implementations.
2. **Shape and behavior live together.** A spec describes both what a function consumes and produces and what it must do.
3. **Explicit authority.** Access to resources, and the ability to fail, are explicit values passed to functions, never ambient powers.
4. **Whole-program spec reuse.** A value constructed in one spec can be catalogued and reused by others.
5. **Effect-free deterministic specs.** Specs are pure, deterministic, and replayable.
6. **Parametricity is preserved.** Code cannot inspect the runtime type of a value, so polymorphic specs test real polymorphic contracts.
7. **Minimal core language.** Advanced mechanisms are added only when the core model needs them.

## 3. Surface structure

A Duetto program is a sequence of top-level items: type aliases, production definitions, and spec blocks. This grammar is descriptive, not formal.

```text
Program    ::= TopItem*
TopItem    ::= TypeAlias | Definition | SpecBlock

TypeAlias  ::= type TypeName TypeParams? = TypeExpr
Definition ::= Name "(" ParamList? ")" "=" Expr ";;"
SpecBlock  ::= spec SpecTitle ":" Newline SpecStmt* ";;"

Param      ::= Name | "$" Name
```

A parameter written with `$` receives a second-class value (section 9).

The spec title is part of the grammar, not a string literal. It may contain letters, digits, spaces, and selected punctuation up to the terminating `:` followed by a newline.

```duetto
type Bool = 'true | 'false

answer() = 42
;;

spec the answer is 42:
  x = answer()
  ensure x == 42
;;
```

Expression forms introduced in this revision, `case` over labels and `try`/`handle`, are described in sections 6 and 8.

## 4. Types

### 4.1 Core type forms

- `Int` and `String`
- label singleton types such as `'true`, `'lt`, `'missing`
- unions of labels, such as `'lt | 'eq | 'gt`
- list types `[T]`
- exact record types `{ f1: T1, ..., fn: Tn }`
- open record types `{ f1: T1, .. }` and `{ f1: T1, ..R }`
- function types `(T1, ..., Tn) -> R`
- the bottom type `Never`, the type of expressions that do not return (such as a raise)
- named type aliases `Name(...)`

```duetto
type Bool = 'true | 'false
type OrderingResult = 'lt | 'eq | 'gt
type Ordering(A) = { compare: (A, A) -> OrderingResult }
```

### 4.2 Labels and label unions

Labels are primitive atomic values and singleton types. Duetto has no primitive `Bool`; booleans are the alias `'true | 'false`.

Unions are restricted to labels. A union such as `Int | String`, or a union of record types, is not allowed. Consuming a label union is done by matching on the label (section 6.3), which is ordinary value inspection, not type inspection. A singleton label type is a subtype of any union containing it.

There are no tagged constructors. Data that would conventionally be a tagged union is expressed with records, lists, labels, or by passing functions (continuation style).

### 4.3 Exact records

Records are structural and **exact**: `{ name: String }` is the type of records with exactly the field `name`, and no other. There is no width subtyping. A value of type `{ name: String, age: Int }` cannot be passed where `{ name: String }` is expected; the caller must project the needed fields, or the callee must accept an open record.

### 4.4 Row polymorphism

Open records are written with a row variable:

- `{ name: String, .. }` has at least the field `name`. Each anonymous `..` introduces a fresh, unnamed row variable.
- `{ name: String, ..R }` names the row, so it can be shared across a signature.

A named row is needed when the same unknown fields must appear more than once:

```text
rename : ({ name: String, ..R }, String) -> { name: String, ..R }
```

Anonymous `..` is the common case and cannot express this sharing. Row variables follow the same convention as type variables in specs: an unbound uppercase name introduces a fresh one.

### 4.5 Lists

Lists are primitive: `[T]` in type position, `[x, y, z]` in value position. List deconstruction is planned but not part of v1; until then, production code consumes lists through built-in primitives such as `fold` and `length`.

### 4.6 The empty record as unit

There is no `Unit` type. The empty record `{}` serves that role. A zero-argument function is a function from `{}`, and `answer()` is sugar for `answer({})`.

## 5. Equality

`==` is a built-in language construct. Its behavior cannot be overridden or customized by user code, and it is defined for every first-class value. Both operands must have the same type.

| Value kind | Equality rule |
| --- | --- |
| `Int`, `String`, labels | equal values |
| Lists | same length and pairwise equal elements |
| Records | same fields and pairwise equal field values |
| Functions | same definition site and equal captured values |
| `$` values | not comparable: compile error |

### 5.1 Function equality

Two function values are equal when they originate from the **same definition site** and their **captured variables are equal**, compared recursively with `==`. A function is therefore equal only to itself; an identical function defined elsewhere is different.

```duetto
adder(n) = (x) -> x + n
;;
```

Here `adder(1) == adder(1)` is `'true` and `adder(1) == adder(2)` is `'false`, regardless of when or how often the closures were created. Equality is deterministic and independent of allocation, so values rebuilt from recipes compare equal to the originals.

The compiler must preserve the observable identity of functions. It may not drop captured variables, merge distinct definition sites, or eta-expand in ways that change `==` results.

### 5.2 Equality and open types

Because `==` requires both operands to have the same type, comparisons on open records follow from ordinary typing:

- Two values of `{ name: String, ..R }` with the same `R` can be compared; the hidden fields are compared too.
- Two parameters typed `{ name: String, .. }` have distinct anonymous row variables, so they have different types and cannot be compared.

Since `==` is total over first-class values, no equality constraint is attached to type or row variables.

### 5.3 Equality in specs

A `==` inside a spec constrains only the spec, not the extracted signature. In the identity spec (section 14), `identity` stays fully polymorphic even though the spec compares its result. Equality reaches a public signature only through production code.

## 6. Production language

Everything outside `spec` blocks is production code. Definitions need no type annotations, but their public signatures come from specs (section 12), not from their bodies. Production code may use local inference internally.

```duetto
greet(person) = "Hello, " + person.name
;;
```

### 6.1 Closures

Functions are first-class values and may capture variables from their defining scope. This revision uses `(x) -> body` as placeholder syntax for anonymous functions; the final syntax is open.

### 6.2 Dispatch

Calling a closure is the only form of dynamic dispatch. Calling `ord.compare(a, b)` runs whichever function the record holds; this is how interfaces, resource handles, doubles, and failure capabilities work.

There is **no type-directed dispatch**: no methods looked up by runtime type, no type tests, no runtime overload resolution. Code cannot observe the runtime type of a value. This preserves parametricity, which `some(A)` relies on (section 7.3).

### 6.3 Label case

Label unions are consumed with a `case` expression. It is checked for exhaustiveness against the closed union of the scrutinee's type.

```duetto
sign_name(r) = case r:
  'lt: "less"
  'eq: "equal"
  'gt: "greater"
;;
```

Because booleans are labels, `case` also serves as the conditional; `if` may be added as sugar. The exact syntax of `case` is not fixed.

## 7. Spec language

A spec block contains statements executed in order. Specs are pure and deterministic: they perform no ambient I/O, and interaction with resources goes through explicit values, including scripted doubles (section 11).

```text
SpecStmt ::= Name "=" Expr
           | ensure Expr
```

### 7.1 `ensure`

`ensure` introduces a behavioral obligation. Its expression must evaluate to `'true` or `'false`; `'false` fails the spec. The expressions inside an `ensure` also contribute type constraints.

```duetto
ensure x == 42
ensure ord.compare(a, b) == 'lt
```

### 7.2 `some(T)`

`some(T)` is available only in specs and denotes a generated value of type `T`. It has two meanings:

- **Statically**, it contributes type information and is the main bridge between testing and polymorphism.
- **Dynamically**, it produces concrete values using the deterministic, replayable generator system.

An unbound uppercase identifier in type position introduces a fresh type variable, and an unbound `..R` introduces a fresh row variable.

```duetto
x = some(Int)
xs = some([A])
p = some({ name: String, .. })
```

### 7.3 Abstract types and parametricity

For a type variable `A`, `some(A)` generates opaque values that support only `==`. Because Duetto has no type-directed dispatch (section 6.2), production code cannot inspect these values, so a spec that passes for opaque values tests the real polymorphic contract.

### 7.4 What `some` can synthesize

`some(T)` synthesizes values only for **function-free** types: `Int`, `String`, labels and label unions, and lists and records built from those. Abstract type variables are instantiated per catalogued type (section 10.6).

A type that contains a function anywhere, transitively, cannot be synthesized. This includes `(Int) -> Int`, `[(Int) -> Int]`, `Ordering(Int)`, and `{ name: String, compare: ... }`. For these, `some(T)` draws a whole value from the **recipe catalogue** (section 10.5). Data fields are never synthesized separately from function fields, since that could break invariants between them.

If no recipe for `T` exists, the spec cannot run, and the compiler reports it: "no spec constructs an `Ordering(Int)`." The standard library ships recipes for common cases, such as the natural orderings on `Int` and `String`.

`some` has one meaning everywhere. A law spec checking an ordering and a sorting spec relying on one both draw from the same catalogue, and recipe-derived values are presumed good.

### 7.5 `every` in laws

`every(T)` is a variant of `some` used only in law specs (section 10.3). It binds the implementation **under test**, while any `some` of an interface type in the same spec is assumed lawful. `every` is valid only on function-carrying types; on a function-free type it would mean the same as `some`, so it is a compile error.

### 7.6 Function-free and function-carrying types

The distinction between function-free types (synthesizable by `some`) and function-carrying types (drawn from recipes) is internal to the compiler and test runner. It has no surface syntax: production code never needs to restrict a parameter to synthesizable types.

## 8. Failure as a capability

The ability to fail is an explicit value, like a filesystem handle. A function can abort only if it was given a raiser. There are no ambient exceptions.

### 8.1 Concepts

1. `try` introduces a **failure capability**: a record of raisers, bound to a `$`-name.
2. Each `handle` clause defines **one raiser** of that record, together with the code that runs when it is called.
3. Calling a raiser **unwinds** to its `try` and runs the matching `handle` clause. The value of that clause becomes the value of the `try` expression.

```duetto
config = try $errs:
  text = read_file(fs, path, $errs.not_found)
  parse_config(text, path, $errs.parse_error)
handle not_found(e):
  default_config()
handle parse_error(e):
  log_and_default(e.path, e.line)
;;
```

The syntax is provisional; the three concepts are the requirement.

### 8.2 Types

In the example, `$errs` has the exact record type:

```text
{ not_found:   ({ path: String }) -> Never,
  parse_error: ({ path: String, line: Int }) -> Never }
```

- Each raiser returns `Never`, so a raise can appear in any expression position.
- Each error kind has its own exactly typed payload record. The field name acts as the tag, so no tagged values exist as data.
- Handler clause names correspond one-to-one with the capability's fields.

### 8.3 Passing narrow capabilities

Because records are exact, a function that can fail in only one way should receive a single raiser, as in `read_file(fs, path, $errs.not_found)`. This is the recommended style: each call shows exactly how it may fail, and specs extract a small exact type. When a function needs several raisers, it receives them individually, or as an open record (`{ not_found: ..., .. }`).

### 8.4 Error translation

A handler clause may call a raiser from an enclosing `try`, which rewraps errors across layers:

```duetto
handle parse_error(e):
  $app_errs.bad_config({ path: e.path, line: e.line, reason: "syntax" })
```

### 8.5 Higher-order code

Higher-order functions need no effect annotations. A callback that may fail captures a raiser; the function receiving it takes a `$`-parameter (section 9) and stays an ordinary parametric function.

```duetto
values = try $errs:
  map(lines, (line) -> parse_int(line, $errs.bad_number))
handle bad_number(e):
  []
;;
```

## 9. Second-class values: the `$` sigil

Some values must not outlive the scope that created them. A raiser called after its `try` has returned would have nowhere to unwind to. Duetto marks such values with the `$` sigil and checks the restriction statically, so a developer sees at every use site that a value is special.

### 9.1 Rules

1. Only `$`-names can hold second-class values. `$`-names are introduced by `try` and by `$`-parameters.
2. Any expression rooted at a `$`-name is second-class. A function value that captures a `$`-name is second-class too.
3. A second-class value can be called, projected (`$errs.not_found`), bound to another `$`-name, or passed to a `$`-parameter. It cannot be returned, stored in a record or list, bound to a plain name, or compared with `==`.
4. A first-class value may be passed to a `$`-parameter, because the parameter only promises that the callee will not let the value escape.

```duetto
$nf = $errs.not_found              -- allowed
nf = $errs.not_found               -- error: plain name
r = { on_missing: $errs.not_found } -- error: stored in a record
```

### 9.2 `$`-parameters in higher-order code

By rule 4, `map(xs, $f)` accepts both ordinary functions and closures that capture raisers. Library authors should mark a function parameter with `$` whenever the function only calls it and never stores or returns it, which is the common case. In a signature, `$f` documents "this is only called."

Spec extraction follows the same model: a spec that passes a capturing callback to `map` establishes that `map`'s parameter is a `$`-parameter.

### 9.3 Interaction with recipes

Recipes are values catalogued from specs. Because second-class values cannot be stored or returned, no recipe can contain a capability. This rules out a value captured inside one spec's `try` being reused, with a dead raiser, by an unrelated spec.

### 9.4 Payloads

Payloads passed to raisers are first-class values, so they cannot contain `$` values. A capability can never escape its `try` through an error payload.

## 10. Interfaces, laws, and recipes

### 10.1 Interfaces as ordinary values

Duetto has no typeclasses or dedicated capability types. Interfaces are ordinary records of functions, passed explicitly:

```duetto
type Ordering(A) = { compare: (A, A) -> OrderingResult }
type Reader = { read_text: (String) -> String }

sort_by(xs, ord) = ...
;;
```

This keeps authority and behavior explicit and works naturally with structural typing. Whether a record represents authority is a property of the runtime model, not a type-system marker. Failure capabilities (section 8) are the one exception: they are second-class.

### 10.2 Shape versus behavior

A value of type `Ordering(A)` has the shape of an ordering, but that does not imply it is transitive or reflexive. Specs keep the two together: shape is extracted from the types used in specs, and behavior is checked by `ensure` in the same specs.

### 10.3 Reusable law specs

The standard library may define generic law specs, such as reflexivity, sign symmetry, and transitivity for `Ordering(A)`. Because a program is compiled and tested as a whole, these law specs can be applied to every implementation of the interface that the program's specs construct.

> If a program introduces a new implementation of an interface and has specs constructing it, generic law specs for that interface are automatically applied to it during whole-program testing.

This is reusable conformance testing, not a static proof.

### 10.4 Spec-derived recipes

Each spec has up to three outputs: type constraints, runtime tests, and **construction recipes**. A recipe is a catalogued description of how a spec deterministically builds a value of some type `T`.

```duetto
spec config file yields ordering:
  fs = double:
    read_text("config.txt") returns "by_name"
  ;;
  ord = load_ordering(fs, "config.txt")
  ensure ord.compare(foo1, foo2) == 'lt
;;
```

This spec can yield a recipe for `Ordering(Foo)`, which law specs can then reuse. Recipes never contain second-class values (section 9.3).

Coverage extends only to construction paths that some spec describes; it grows as specs become more generative.

### 10.5 The recipe catalogue

A recipe enters the catalogue only after the spec that constructs it **passes**. Recipes are never admitted provisionally, so the catalogue only grows and nothing is ever removed.

Specs run in rounds until a fixed point:

1. Statically, each spec **needs** the recipe types of its function-carrying `some(...)` and **produces** the function-carrying values it constructs.
2. Round 0 runs the specs that need no recipes. Each passing spec adds its recipes to the catalogue.
3. Each later round runs the specs whose needs are now covered, including earlier specs re-run with newly available types. Passing specs add more recipes.
4. Evaluation stops when a round adds no recipe, or when the **recursion limit** is reached.

The same spec may therefore run several times, with different concrete types, at different points. Recipes may be built from other recipes, as in `lexicographic(ord)` producing an `Ordering([A])` from an `Ordering(A)`; the recursion limit bounds this depth. A cap on instantiations per spec may also be needed to control cost.

A spec that can never run is reported. If the only spec constructing an `Ordering(Foo)` itself needs an `Ordering(Foo)`, there is no base case: "no grounded recipe for `Ordering(Foo)`."

### 10.6 Law specs over catalogued types

Recipes are concrete, such as `Ordering(Foo)`, while law specs are generic, such as reflexivity over `Ordering(A)`. A generic spec runs once per catalogued type, with `A := Foo`; its `some(A)` then produces `Foo` values, synthesized if `Foo` is function-free and drawn from recipes otherwise.

Law specs do not gate admission. A recipe used by a sorting spec may also be checked by a law spec in the same round. A broken implementation can therefore cause a small cascade of failures, which section 10.8 addresses.

### 10.7 Doubles and recipes

A double is never itself catalogued as a recipe. A recipe may still contain doubles that its construction needed, such as an ordering built by `load_ordering(fs_double, ...)`.

When a recipe is reused in another spec, its doubles keep answering their **stubbed** calls, so the value still works, but their call logs are not checked: expectations belong to the spec that primed them (section 11.2). If a reused recipe calls a contained double with an input that was never stubbed, there is no answer to give; that call invalidates the recipe instead of failing the spec that borrowed it. Blame stays with the recipe's source.

### 10.8 Failure reporting

The runner tracks which recipes each spec used, and groups failures to point at a likely root cause:

- Failures that share a recipe are grouped under that recipe.
- If a law spec for the recipe's type failed on it, that failure is reported first as the likely cause: "`ordering compare is reflexive` failed on the `Ordering(Foo)` from `config file yields ordering`; 7 other failing specs used the same value."
- A spec that fails with some recipes and passes with others points at those recipes. A spec that fails with all of them points at the code under test.

Law specs are scheduled early within each round, without gating anything, so the root cause is usually present in the report.

### 10.9 Declaring laws

A spec is a **law spec** when its title marks one or more interface names in backticks:

```duetto
spec `Ordering` is symmetric:
  ord = every(Ordering(A))
  x = some(A)
  y = some(A)
  ensure ord.compare(x, y) == flip(ord.compare(y, x))
;;
```

Rules:

- A backticked name in a title is an **identifier**, not text. It must resolve to a type alias in scope; tooling treats it as code (renaming, go-to-definition). The rest of the title remains free text.
- The marked name is the type constructor. `` `Ordering` `` permits `every(Ordering(X))` for any `X`.
- Each marked name must be bound by **exactly one** `every(...)` in the body. A marked name with no `every`, or with more than one, is a compile error. This may be relaxed later if a law needs several subjects of one interface.
- `every` may appear only in law specs, and only on names marked in the title.
- Any `some` of an interface type in a law spec is assumed lawful. A law relating two interfaces marks both: ``spec `Ordering` agrees with `Eq`:``.

The marker drives the failure reporter (section 10.8) today. In the future, it is what allows a law spec to be read as a logical statement: a schema over every implementation of the marked interfaces, with the lawfulness of the other interface values as hypotheses.

## 11. Scripted doubles

Doubles are a core language feature, not a library, because specs must be writable before any helper framework exists. Their surface syntax is provisional.

- A spec can construct a test value standing in for a dependency.
- The double has an ordinary structural type, typically an exact record of functions.
- The spec **stubs** responses for specific inputs.
- A call with an input that was not stubbed fails the spec.
- Expected interactions are checked explicitly, with `calls` (section 11.2).

```duetto
spec loading settings works:
  fs = double:
    read_text("settings.json") returns "{ theme: \"dark\" }"
  ;;
  settings = load_settings(fs, "settings.json")
  ensure settings.theme == "dark"
;;
```

Statically, this double contributes `{ read_text: (String) -> String }`.

### 11.1 Doubles for raisers

A double can stand in for a raiser and script an expected failure. This both tests the failure path and contributes the raiser's payload type to the extracted signature.

```duetto
spec missing file is reported:
  fs = double:
    read_text("a.cfg") raises not_found({ path: "a.cfg" })
  ;;
  ...
;;
```

### 11.2 Checking interactions with `calls`

`calls(double.fn)` is a spec-only builtin returning the list of argument records `fn` has received so far. Expectations become ordinary `ensure`s:

```duetto
spec settings are read once:
  fs = double:
    read_text("settings.json") returns "{ theme: \"dark\" }"
  ;;
  settings = load_settings(fs, "settings.json")
  ensure settings.theme == "dark"
  ensure calls(fs.read_text) == [{ path: "settings.json" }]
;;
```

- A call count is `length(calls(...))`; arguments and order can be checked too.
- `calls` accepts only a double **primed by name in the current spec**. Doubles inside recipe values are never reachable by name from a consuming spec, so their expectations are never checked. This rule needs no special case: it follows from scoping.
- There is no implicit "missing interactions fail" rule; required interactions are stated with `ensure`.
- Any `ensure` that mentions `calls` is a trace check. All other `ensure`s are statements about values, which keeps the non-logical parts of a spec syntactically visible.

## 12. Type extraction and production checking

### 12.1 Extraction

Type extraction is constraint-based over spec bodies. Each spec binding has an inferred type, each call to production code constrains argument and result types, and each `ensure` may add constraints.

```duetto
spec greeting works:
  x = greet({ name: "Ada" })
  ensure x == "Hello, Ada"
;;
```

With exact records, this establishes exactly `greet : ({ name: String }) -> String`. Constraints from several specs on the same function are combined by unification, not by searching for a common supertype.

### 12.2 Polymorphism

Fresh type and row variables introduced by `some(...)` are generalized:

```duetto
spec identity returns its input:
  x = some(A)
  y = identity(x)
  ensure y == x
;;
```

This contributes `identity : (A) -> A`, universally quantified over `A`. A spec using `some({ name: String, .. })` contributes an open-record parameter.

### 12.3 Labels (proposed)

The set of labels a function accepts is the union of the labels its specs pass to it. Specs calling `f('true)` and `f('false)` give `f : ('true | 'false) -> ...`. Every accepted label then has at least one spec exercising it. `some(Bool)` covers the generative case.

### 12.4 Second-class parameters

A parameter receives a `$` marking when any spec passes it a second-class value. A production definition may also declare a parameter `$`, which constrains its own body.

### 12.5 Checking pipeline

1. Collect and elaborate all spec blocks.
2. Extract public signatures.
3. Typecheck production definitions against those signatures.
4. Execute specs in rounds, admitting each passing spec's recipes to the catalogue, until a fixed point or the recursion limit (section 10.5).
5. Report failures grouped by shared recipes (section 10.8).

An implementation cannot strengthen its required input shape or change its return type beyond what the specs establish. When a check fails, diagnostics should identify which spec contributed each conflicting constraint.

## 13. Open questions and deferred areas

### 13.1 Open questions

- **Evaluation cost.** Re-running specs for each newly catalogued type can grow quickly. The recursion limit may need a companion cap on instantiations per spec, or sampling.
- **Generalization from concrete literals.** Specs that use only concrete values produce monomorphic signatures. A warning suggesting `some(...)` may help.
- **Unconstrained results.** If no spec inspects a function's result, its return type is unconstrained.
- **Overloaded `raise`.** A single overloaded raiser, with payloads told apart by a label field, would require intersection types and effectively reintroduce discriminated unions. Named raisers are the current design.
- **Termination.** Reading `some` specs as proofs would require totality of the production functions involved, probably through an opt-in marker. Without it, the logical reading is partial correctness.
- **Exact syntax** for `case`, `try`/`handle`, anonymous functions, doubles, and comments.

### 13.2 Deferred

- List deconstruction and pattern matching (planned)
- Recursive type aliases (likely needed early, for trees as `{ value: A, children: [Tree(A)] }`)
- Formal rules for label subtyping and function variance
- Mutable state
- Exact generator semantics for all `some(T)` forms
- Modules and visibility. Abstract types will need a way to state whether `==` may see through them.
- An exhaustive formal grammar and operational semantics

## 14. Examples

### 14.1 Exact structural input

```duetto
greet(person) = "Hello, " + person.name
;;

spec greeting works:
  x = greet({ name: "Ada" })
  ensure x == "Hello, Ada"
;;
```

Extracted: `greet : ({ name: String }) -> String`.

### 14.2 Open input

```duetto
spec greeting ignores other fields:
  p = some({ name: String, .. })
  ensure greet(p) == "Hello, " + p.name
;;
```

Extracted: `greet : ({ name: String, .. }) -> String`.

### 14.3 Polymorphic identity

```duetto
identity(x) = x
;;

spec identity returns its input:
  x = some(A)
  y = identity(x)
  ensure y == x
;;
```

Extracted: `identity : (A) -> A`.

### 14.4 Sorting with an explicit ordering

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

### 14.5 Failure handling

```duetto
port = try $errs:
  parse_int(text, $errs.bad_number)
handle bad_number(e):
  8080
;;
```

Here `parse_int` receives a single raiser of type `({ text: String }) -> Never` and cannot store it.

## 15. Summary

Duetto is a whole-program language in which specifications are executable code defining what production code may consume and produce, what it must do, and how values can be constructed for further conformance testing. Data is exact records, lists, and labels; choice is expressed by label `case` or by calling closures; failure is a second-class capability passed explicitly; and equality is built in and total. The duet between spec and production code is the reason for the name.
