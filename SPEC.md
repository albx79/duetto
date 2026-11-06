# Duetto Language Draft Specification

Nov 5, 2026 · @Alb

## 1. Overview

Duetto is a whole-program language with two tightly integrated sublanguages: **spec**, for executable specifications and tests, and **prod**, for production code. Spec entries, introduced with `spec`, belong to the spec sublanguage; everything else is prod. Source files use the extension `.duetto`.

The central design principle:

> Production code receives its public type information from specifications.

Specs serve three purposes at once:

1. **Type extraction**: inferring public signatures from how specs use production code.
2. **Test execution**: checking runtime behavior.
3. **Recipe extraction**: cataloguing how values of interesting types are constructed, for reuse in other specs.

### 1.1 Changes in this revision

- **Braces replace `;;` and indentation.** A file is a struct, a struct is a module, and a block is a brace group ending in a `<<` result. Entries are comma-separated, and newlines are not significant.
- **One binding form.** Functions are lambdas bound to names: `adder = n -> x -> x + n`. Lambda literals in a struct form a recursive group.
- **Fields are public, locals are private.** `name: expr` is part of a struct and, at file level, exported; `name = expr` is visible only to later entries.
- **Type variables are marked** with `?` at their first occurrence: `some(?A)`.
- Records are **exact** by default, with opt-in row polymorphism: `{ f: T, .. }` and `{ f: T, ..?R }`.
- Unions are restricted to **unions of labels**, eliminated by an exhaustive `case`.
- **No type-directed dispatch**; closures are the only form of dynamic dispatch.
- `==` is **built-in, total, and non-overridable**; functions compare by definition site plus captured values.
- Failure is a **capability** introduced by `try`, whose raisers are defined by the branches of a following `case`.
- **No `type` keyword.** Uppercase entry names bind types, with the same `:` (public) and `=` (private) rule as values.
- The **`$` sigil** marks second-class, non-escaping values.
- `some(T)` synthesizes only **function-free** values; function-carrying values come from a **recipe catalogue**.
- **Law specs** mark interfaces in backticks in their titles and bind each with exactly one `every(...)`.
- Double expectations are explicit `ensure`s over **`calls`**.

## 2. Design goals

1. **Specs define interfaces.** Public signatures are inferred from spec usage, not from implementations.
2. **Shape and behavior live together.** A spec describes both what a function consumes and produces and what it must do.
3. **Explicit authority.** Access to resources, and the ability to fail, are explicit values passed to functions, never ambient powers.
4. **Whole-program spec reuse.** A value constructed in one spec can be catalogued and reused by others.
5. **Effect-free deterministic specs.** Specs are pure, deterministic, and replayable.
6. **Parametricity is preserved.** Code cannot inspect the runtime type of a value, so polymorphic specs test real polymorphic contracts.
7. **Few constructs.** One grouping construct, the brace group, serves as record, block, and module.

## 3. Surface structure

### 3.1 Files, structs, and modules

A Duetto file is the body of a struct: a comma-separated sequence of entries. Every brace group is made of the same entries, so a file, a module, and a record literal are one construct. A file is a module, and importing it yields a record (import syntax is not yet fixed).

```duetto
Bool: 'true | 'false,

answer: () -> 42,

spec the answer is 42 {
  x = answer(),
  ensure x == 42,
},
```

Entries are separated by commas, and a trailing comma is allowed. Newlines and indentation are not significant.

### 3.2 Entries

This grammar is descriptive, not formal.

```text
File     ::= Entries
Struct   ::= "{" Entries "}"
Entries  ::= (Entry ("," Entry)* ","?)?

Entry    ::= name ":" Expr             -- field
           | Path                      -- punned field: { x }, { p.name }, { Bool }
           | name "=" Expr             -- local
           | "$" name "=" Expr         -- second-class local
           | TypeName TypeParams? ":" TypeExpr   -- public type
           | TypeName TypeParams? "=" TypeExpr   -- private type
           | spec SpecTitle Struct
           | ensure Expr               -- spec bodies only
           | do Expr                   -- an effect; Expr : {}
           | "<<" Expr                 -- block result; last entry
```

Here `name` starts with a lowercase letter and `TypeName` with an uppercase letter (section 3.8).

- **Fields** (`name: expr`) are part of the struct's type and value. At file level, they are the module's exports.
- **Locals** (`name = expr`) are visible to later entries but are not part of the struct. At file level, they are private. Types follow the same `:` and `=` rule (section 3.8).
- **Punning** works for names and paths only: `{ x }` means `{ x: x }`, and `{ p.name }` means `{ name: p.name }`.
- **Spec entries** contribute no fields.

### 3.3 Blocks

A brace group whose last entry is `<<expr` is a **block**, and its value is `expr`. A block may not contain fields; a brace group without `<<` is a record.

```duetto
total = {
  tmp1 = price(order),
  tmp2 = shipping(order),
  <<tmp1 + tmp2
},
```

This is sugar for `{ tmp1 = ..., tmp2 = ..., res: tmp1 + tmp2 }.res`.

`do expr` runs `expr` for its effect without naming the result. Its type must be `{}`, so a real result cannot be discarded silently.

### 3.4 Lambdas

```text
Lambda ::= Params "->" Expr
Params ::= Param | "(" (Param ("," Param)*)? ")"
Param  ::= Name | "$" Name
```

```duetto
adder = n -> x -> x + n,
sort_by = (xs, ord) -> ...,
map = (xs, $f) -> ...,
answer = () -> 42,
```

There is no separate function-definition form. A lambda body extends as far right as possible, ending at a comma, a closing bracket, or the end of its entry. A longer body is a block: `x -> { ..., <<result }`. A `$` parameter receives a second-class value (section 9).

### 3.5 Scoping and recursion

The same rule applies in every struct: files, modules, records, and blocks, for fields and locals alike.

- Bindings whose right-hand side is a **lambda literal** form one recursive group. They can refer to themselves and to each other in any order, and their bodies may mention any binding in the struct.
- Every other binding is **computed**, and is visible only to later entries.
- **Initialization order.** For each computed binding `b`, collect the lambdas reachable from `b`'s initializer: those it mentions, then those they mention, transitively. Every computed binding those lambdas mention must come **before** `b`. This guarantees that no computation can read a binding that is not yet initialized.

```duetto
{
  f = make_adder(1),   -- computed: backward-only
  g = x -> h(f(x)),    -- lambda: may call h, defined later
  h = x -> x * 2,
}
```

Checking a computed binding against a lambda's own position is not enough, because a hoisted lambda can be called before its position. This block is rejected:

```duetto
{
  f = x -> g(x),
  f_res = f(1),
  g = x -> x * f_res,
  <<f_res
}
```

`f_res` reaches `f`, then `g`; `g` mentions `f_res`, which does not come before `f_res`:

```text
f_res is used before it is initialized:
  f_res calls f, f calls g, g reads f_res
```

"Mentions" is conservative: a lambda passed as a value counts as possibly called, since a higher-order callee might call it. The rule may therefore reject a few programs that would run, but it never accepts one that reads an uninitialized value. Unlike anchoring the whole recursive group at its first member, it does not force constants above the first function in a file; it reports only real paths from a computation back to itself.

### 3.6 Spec entries

A spec entry is `spec`, a title, and a struct. The title is part of the grammar, not a string literal: free text up to the opening `{`, so it cannot contain braces. Names in backticks are identifiers that mark a law (section 10.9).

### 3.7 Comments

Comment syntax is not yet fixed; this draft uses `--`.

### 3.8 Type entries

There is no `type` keyword. **An entry whose name starts with an uppercase letter binds a type**, and its right-hand side is parsed as a type expression. A lowercase name binds a value; labels are marked with `'`. As with values, `:` makes a type public and `=` keeps it private:

```duetto
Bool: 'true | 'false,                                -- public type
OrderingResult: 'lt | 'eq | 'gt,
Ordering(A): { compare: (A, A) -> OrderingResult },
Pair = { first: Int, second: Int },                  -- private type
```

- Parameters at the head of an entry, as in `Ordering(A): ...`, can only mean a type constructor, since values have no `name(params)` form.
- Punning works for types: `{ Bool }` re-exports a type from elsewhere.
- Value names must start with a lowercase letter.

**Type members are transparent and static.** Because a file is a struct and structs are first-class records, public types are members of a record type. For now they are transparent aliases: `m.Bool` is another name for `'true | 'false`, so no dependent typing is needed. Type members exist only at compile time and do not take part in a record's runtime value, its exactness, or `==`. Abstract types, where a type member would become genuinely dependent, are deferred (section 13.2).

## 4. Types

### 4.1 Core type forms

- `Int` and `String`
- label singleton types such as `'true`, `'lt`, `'missing`
- unions of labels, such as `'lt | 'eq | 'gt`
- list types `[T]`
- exact record types `{ f1: T1, ..., fn: Tn }`
- open record types `{ f1: T1, .. }` and `{ f1: T1, ..?R }`
- function types `(T1, ..., Tn) -> R`
- the bottom type `Never`, the type of expressions that do not return (such as a raise)
- named type aliases `Name(...)`

```duetto
Bool: 'true | 'false,
OrderingResult: 'lt | 'eq | 'gt,
Ordering(A): { compare: (A, A) -> OrderingResult },
```

### 4.2 Labels and label unions

Labels are primitive atomic values and singleton types. Duetto has no primitive `Bool`; booleans are the alias `'true | 'false`.

Unions are restricted to labels. A union such as `Int | String`, or a union of record types, is not allowed. Consuming a label union is done by matching on the label (section 6.3), which is ordinary value inspection, not type inspection. A singleton label type is a subtype of any union containing it.

There are no tagged constructors. Data that would conventionally be a tagged union is expressed with records, lists, labels, or by passing functions. Section 13.4 plans two extensions instead of tagged unions: **untagged unions of labels and records**, and **handler-interface `case` sugar**.

### 4.3 Exact records

Records are structural and **exact**: `{ name: String }` is the type of records with exactly the field `name`, and no other. There is no width subtyping. A value of type `{ name: String, age: Int }` cannot be passed where `{ name: String }` is expected; the caller must project the needed fields, or the callee must accept an open record.

### 4.4 Row polymorphism

Open records are written with a row variable:

- `{ name: String, .. }` has at least the field `name`. Each anonymous `..` introduces a fresh, unnamed row variable.
- `{ name: String, ..?R }` names the row, so it can be shared across a signature.

A named row is needed when the same unknown fields must appear more than once:

```text
rename : ({ name: String, ..?R }, String) -> { name: String, ..R }
```

Anonymous `..` is the common case and cannot express this sharing.

### 4.5 Lists

Lists are primitive: `[T]` in type position, `[x, y, z]` in value position. List deconstruction is planned but not part of v1; until then, production code consumes lists through built-in primitives such as `fold` and `length`.

### 4.6 The empty record as unit

There is no `Unit` type. The empty record `{}` serves that role. A zero-argument lambda `() -> 42` is a function from `{}`, and `answer()` is sugar for `answer({})`.

### 4.7 Type variables

A type or row variable is introduced by prefixing its **first occurrence** with `?`; later occurrences are bare. Multi-letter names are allowed.

```duetto
x = some(?Key),
ys = some([Key]),
```

- In a spec, the scope of a type variable is the enclosing spec. In an extracted signature, it is the signature.
- Type alias parameters, as in `Ordering(A): ...`, are already in binding position and need no `?`.
- A bare name that does not resolve to a type is an error. A typo such as `Strng` is reported, instead of silently becoming a fresh type variable.

Since production code has no type annotations, `?` appears only in specs and extracted signatures.

### 4.8 No tuples

Duetto has no tuples. Parentheses mean grouping and parameter lists only, and `(x, y) -> ...` is a parameter list, not a tuple pattern.

Tuples could be added cheaply as sugar for records with numeric fields, as in Standard ML, but their main appeal would be unifying them with argument lists, so that every function takes a single argument. That unification conflicts with second-class values: in `map = (xs, $f) -> ...`, the argument tuple would be a record holding a `$` value, which fields can never hold. Without the unification, the remaining benefit is small. Named records serve better, and cost no more to write:

```duetto
divmod = (a, b) -> { div: a / b, mod: a % b },
```

For generic code, the standard library picks field names once, as in `zip` returning `[{ left: A, right: B }]`.

This decision will be revisited only if an elegant way is found to unify tuples with argument lists, even in the presence of `$` values.

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

Two function values are equal when they originate from the **same lambda literal** and their **captured variables are equal**, compared recursively with `==`. A function is therefore equal only to itself; an identical function written elsewhere is different.

**Identity is defined over the recursive group instance.** References to members of a lambda's own recursive group (section 3.5) are not captures. Instead, a closure's identity is its lambda site plus the external captures of **all members of its recursive group**. Computing captures per lambda would be wrong, because a group member may reach an external value only through a sibling:

```duetto
make = n -> {
  even = k -> case k == 0 { 'true -> 'true, 'false -> odd(k - 1) },
  odd = k -> case k == n { 'true -> 'false, 'false -> even(k - 1) },
  <<even
},
```

`even` captures nothing from outside its group; only `odd` captures `n`. With per-lambda captures, `make(1) == make(2)` would be `'true` although the two functions behave differently. With group-instance identity, both closures carry the group's external capture `n`, so they differ.

**Termination.** Equality always terminates. The group environment excludes group members, so comparing it never re-enters the group. Captured data is acyclic because values are immutable and because the **initialization-order rule** (section 3.5) rejects any path from a computed binding back to itself: no captured value can contain a closure of the group that captures it. This rule is therefore a precondition of equality terminating.

**Determinism.** Identity depends only on lambda sites and values, never on allocation.

```duetto
adder = n -> x -> x + n,
```

Here `adder(1) == adder(1)` is `'true` and `adder(1) == adder(2)` is `'false`, regardless of when or how often the closures were created. Equality is deterministic and independent of allocation, so values rebuilt from recipes compare equal to the originals.

The compiler must preserve the observable identity of functions. It may not drop captured variables, merge distinct lambda literals, or eta-expand in ways that change `==` results.

### 5.2 Equality and open types

Because `==` requires both operands to have the same type, comparisons on open records follow from ordinary typing:

- Two values of `{ name: String, ..R }` with the same `R` can be compared; the hidden fields are compared too.
- Two parameters typed `{ name: String, .. }` have distinct anonymous row variables, so they have different types and cannot be compared.

Since `==` is total over first-class values, no equality constraint is attached to type or row variables.

### 5.3 Equality in specs

A `==` inside a spec constrains only the spec, not the extracted signature. In the identity spec (section 14.3), `identity` stays fully polymorphic even though the spec compares its result. Equality reaches a public signature only through production code.

## 6. Production language

Everything that is not a spec entry is production code. Definitions need no type annotations. The signatures of fields come from specs (section 12); the types of locals come from local inference.

```duetto
greet: person -> "Hello, " + person.name,
```

### 6.1 Closures

Functions are first-class values and may capture variables from their defining scope. There is no separate function-definition form: a function is a lambda bound to a name (section 3.4).

### 6.2 Dispatch

Calling a closure is the only form of dynamic dispatch. Calling `ord.compare(a, b)` runs whichever function the record holds; this is how interfaces, resource handles, doubles, and failure capabilities work.

There is **no type-directed dispatch**: no methods looked up by runtime type, no type tests, no runtime overload resolution. Code cannot observe the runtime type of a value. This preserves parametricity, which `some(?A)` relies on (section 7.3).

### 6.3 Label case

Label unions are consumed with `case`. It is checked for exhaustiveness against the closed union of the scrutinee's type. Branches are comma-separated; a branch body is an expression or a block.

```duetto
sign_name: r -> case r { 'lt -> "less", 'eq -> "equal", 'gt -> "greater" },
```

Because booleans are labels, `case` also serves as the conditional; `if` may be added as sugar.

### 6.4 Effects

An effect performed through a capability, such as writing a file, is run with `do` when its result is not needed (section 3.3). The expression after `do` must have type `{}`.

```duetto
save: (fs, path, text) -> {
  do fs.write_text(path, text),
  <<path
},
```

## 7. Spec language

A spec entry's body is a struct whose entries run in order: locals and `ensure` statements. Specs are pure and deterministic: they perform no ambient I/O, and interaction with resources goes through explicit values, including scripted doubles (section 11). A spec sees the fields and locals of its enclosing struct.

### 7.1 `ensure`

`ensure` introduces a behavioral obligation. Its expression must evaluate to `'true` or `'false`; `'false` fails the spec. The expressions inside an `ensure` also contribute type constraints.

```duetto
ensure x == 42,
ensure ord.compare(a, b) == 'lt,
```

### 7.2 `some(T)`

`some(T)` is available only in specs and denotes a generated value of type `T`. It has two meanings:

- **Statically**, it contributes type information and is the main bridge between testing and polymorphism.
- **Dynamically**, it produces concrete values using the deterministic, replayable generator system.

Type and row variables are introduced with `?` at their first occurrence (section 4.7).

```duetto
x = some(Int),
xs = some([?A]),
p = some({ name: String, .. }),
```

### 7.3 Abstract types and parametricity

For a type variable `?A`, `some(?A)` generates opaque values that support only `==`. Because Duetto has no type-directed dispatch (section 6.2), production code cannot inspect these values.

The guarantee is **parametricity up to equality**. Every Duetto type supports `==`, so "for all `A`" already means "for all `A`, with equality": a function of type `(?A) -> A` must still be the identity, but one of type `(?A, A) -> A` may branch on whether its arguments are equal. To exercise such branches, the generator for abstract types must **produce collisions**, sometimes generating equal values, rather than tokens that are always distinct.

### 7.4 What `some` can synthesize

`some(T)` synthesizes values only for **function-free** types: `Int`, `String`, labels and label unions, and lists and records built from those. Abstract type variables are instantiated per catalogued type (section 10.6).

A type that contains a function anywhere, transitively, cannot be synthesized. This includes `(Int) -> Int`, `[(Int) -> Int]`, `Ordering(Int)`, and `{ name: String, compare: ... }`. For these, `some(T)` draws a whole value from the **recipe catalogue** (section 10.5). Data fields are never synthesized separately from function fields, since that could break invariants between them.

If no recipe for `T` exists, the spec cannot run, and the compiler reports it: "no spec constructs an `Ordering(Int)`." The standard library ships recipes for common cases, such as the natural orderings on `Int` and `String`.

`some` has one meaning everywhere. A law spec checking an ordering and a sorting spec relying on one both draw from the same catalogue, and recipe-derived values are presumed good.

### 7.5 `every` in laws

`every(T)` is a variant of `some` used only in law specs (section 10.9). It binds the implementation **under test**, while any `some` of an interface type in the same spec is assumed lawful. `every` is valid only on function-carrying types; on a function-free type it would mean the same as `some`, so it is a compile error.

### 7.6 Function-free and function-carrying types

The distinction between function-free types (synthesizable by `some`) and function-carrying types (drawn from recipes) is internal to the compiler and test runner. It has no surface syntax: production code never needs to restrict a parameter to synthesizable types.

## 8. Failure as a capability

The ability to fail is an explicit value, like a filesystem handle. A function can abort only if it was given a raiser. There are no ambient exceptions.

### 8.1 Concepts

1. `try` introduces a **failure capability**: a record of raisers, bound to a `$`-name. Its body is a block.
2. A `case` directly after the `try` block lists the **handler branches**. Each branch defines **one raiser** of that record, together with the expression or block that runs when it is called.
3. Calling a raiser **unwinds** to its `try` and runs the matching branch. The value of that branch becomes the value of the `try` expression; if no raiser is called, the value is the block's result.

```duetto
config = try $errs {
  text = read_file(fs, path, $errs.not_found),
  <<parse_config(text, path, $errs.parse_error)
} case {
  not_found(e) -> default_config(),
  parse_error(e) -> log_and_default(e.path, e.line),
}
```

As with any `case`, the braces may be omitted when there is exactly one branch:

```duetto
port = try $errs {
  <<parse_int(text, $errs.bad_number)
} case bad_number(e) -> 8080,
```

There is no ambiguity with a label `case`. A label `case` has a scrutinee (`case r { ... }`), while a handler `case` follows a `try` block directly; since Duetto has no juxtaposition application, a `case` in that position can only be the handler clause. The branch shapes also differ: labels (`'lt -> ...`) versus raisers (`not_found(e) -> ...`).

### 8.2 Types

In the example, `$errs` has the exact record type:

```text
{ not_found:   ({ path: String }) -> Never,
  parse_error: ({ path: String, line: Int }) -> Never }
```

- Each raiser returns `Never`, so a raise can appear in any expression position.
- Each error kind has its own exactly typed payload record. The raiser's name acts as the tag, so no tagged values exist as data.
- **Handler branches define; label branches cover.** In a label `case`, the branches must cover the scrutinee's type. In a handler `case`, the branches *create* the capability's type: there is nothing to check for exhaustiveness, but using `$errs.foo` with no `foo(e)` branch is an error ("no handler for `foo`").
- A branch such as `not_found(e)` resembles a constructor pattern, but Duetto has no tagged variants: it reads as "the `not_found` raiser was called with `e`." Once patterns exist, the payload may be destructured in place: `parse_error({ path, line }) -> ...`.

### 8.3 Passing narrow capabilities

Because records are exact, a function that can fail in only one way should receive a single raiser, as in `read_file(fs, path, $errs.not_found)`. This is the recommended style: each call shows exactly how it may fail, and specs extract a small exact type. When a function needs several raisers, it receives them individually, or as an open record (`{ not_found: ..., .. }`).

### 8.4 Error translation

A handler branch may call a raiser from an enclosing `try`, which rewraps errors across layers:

```duetto
parse_error(e) -> $app_errs.bad_config({ path: e.path, line: e.line, reason: "syntax" }),
```

### 8.5 Higher-order code

Higher-order functions need no effect annotations. A callback that may fail captures a raiser; the function receiving it takes a `$`-parameter (section 9) and stays an ordinary parametric function.

```duetto
values = try $errs {
  <<map(lines, line -> parse_int(line, $errs.bad_number))
} case bad_number(e) -> [],
```

## 9. Second-class values: the `$` sigil

Some values must not outlive the scope that created them. A raiser called after its `try` has returned would have nowhere to unwind to. Duetto marks such values with the `$` sigil and checks the restriction statically, so a developer sees at every use site that a value is special.

### 9.1 Rules

1. Only `$`-locals, `$`-parameters, and second-class records (section 9.5) can hold second-class values. `$`-names are introduced by `try`, by `$`-locals, and by `$`-parameters. Fields of an ordinary record can never hold them.
2. Any expression rooted at a `$`-name is second-class. A function value that captures a `$`-name is second-class too.
3. A second-class value can be called, projected (`$errs.not_found`), bound to another `$`-local, or passed to a `$`-parameter. It cannot be returned, stored in a field or list, bound to a plain name, or compared with `==`.
4. A first-class value may be passed to a `$`-parameter, because the parameter only promises that the callee will not let the value escape.

```duetto
$nf = $errs.not_found,               -- allowed: second-class local
nf = $errs.not_found,                -- error: plain name
r = { on_missing: $errs.not_found }, -- error: stored in a field
```

### 9.2 `$`-parameters in higher-order code

By rule 4, `map = (xs, $f) -> ...` accepts both ordinary functions and closures that capture raisers. Library authors should mark a function parameter with `$` whenever the function only calls it and never stores or returns it, which is the common case. In a signature, `$f` documents "this is only called."

Spec extraction follows the same model: a spec that passes a capturing callback to `map` establishes that `map`'s parameter is a `$`-parameter.

### 9.3 Interaction with recipes

Recipes are values catalogued from specs. Because second-class values cannot be stored or returned, no recipe can contain a capability. This rules out a value captured inside one spec's `try` being reused, with a dead raiser, by an unrelated spec.

### 9.4 Payloads

Payloads passed to raisers are first-class values, so they cannot contain `$` values. A capability can never escape its `try` through an error payload.

### 9.5 Second-class records and `$` in function types

**Second-class records.** A record literal with any second-class field is itself second-class. Like any second-class value, it may only be called into, projected, bound to a `$`-local, or passed to a `$`-parameter; it cannot be returned or stored.

```duetto
result = e.match({
  num: n -> check(n, $errs.too_big),   -- second-class branch
  add: (l, r) -> ...,
}),                                     -- allowed if match takes a $-parameter
```

**`$` in function types.** A function type may mark a parameter as second-class, so type aliases can express it:

```text
match: ($ { num: (Int) -> ?R, add: (Expr, Expr) -> R }) -> R
```

Without this, `$` would exist only on parameter names, and no alias could describe a function that accepts second-class arguments. Both handler encodings in section 13.4 depend on it.

## 10. Interfaces, laws, and recipes

### 10.1 Interfaces as ordinary values

Duetto has no typeclasses or dedicated capability types. Interfaces are ordinary records of functions, passed explicitly:

```duetto
Ordering(A): { compare: (A, A) -> OrderingResult },
Reader: { read_text: (String) -> String },

sort_by: (xs, ord) -> ...,
```

This keeps authority and behavior explicit and works naturally with structural typing. Whether a record represents authority is a property of the runtime model, not a type-system marker. Failure capabilities (section 8) are the one exception: they are second-class.

### 10.2 Shape versus behavior

A value of type `Ordering(A)` has the shape of an ordering, but that does not imply it is transitive or reflexive. Specs keep the two together: shape is extracted from the types used in specs, and behavior is checked by `ensure` in the same specs.

### 10.3 Reusable law specs

The standard library may define generic law specs, such as reflexivity, sign symmetry, and transitivity for `Ordering(A)`. Because a program is compiled and tested as a whole, these law specs are applied to every implementation of the interface that the program's specs construct.

> If a program introduces a new implementation of an interface and has specs constructing it, generic law specs for that interface are automatically applied to it during whole-program testing.

This is reusable conformance testing, not a static proof. Section 10.9 describes how law specs are declared.

### 10.4 Spec-derived recipes

Each spec has up to three outputs: type constraints, runtime tests, and **construction recipes**. A recipe is a catalogued description of how a spec deterministically builds a value of some type `T`.

```duetto
spec config file yields ordering {
  fs = double { read_text("config.txt") returns "by_name" },
  ord = load_ordering(fs, "config.txt"),
  ensure ord.compare(foo1, foo2) == 'lt,
}
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

**Why lawfulness can be assumed.** A recipe is admitted when its constructing spec passes, which does not by itself establish that it satisfies the laws of its interface. The assumption that `some` values of an interface type are lawful is justified at the level of the **whole run**: law specs are instantiated for every catalogued recipe of their type, so a recipe that breaks a law fails that law spec and the run fails. A green run therefore implies that every recipe used passed every applicable law, as far as testing goes. A failing run may contain spurious failures in specs that consumed a broken recipe; the failure reporter (section 10.8) groups them.

**Law obligations.** Every recipe used by any spec, and every **generated interface value** (section 13.4), must be run through all applicable law specs. Several rules make this complete:

- **Caps never apply to law specs.** Instantiation caps (section 10.5) may limit consumer specs only.
- **Applicable laws** are those whose marked interface is exactly the value's type. A value of interface type nested inside another value, as in `{ name: String, ord: Ordering(Foo) }`, is neither checked nor assumed lawful.
- **Multi-interface laws** are instantiated for every combination of recipes of the marked interfaces with matching type arguments. For `` `Ordering` agrees with `Eq` ``, every `Ordering(X)` recipe is paired with every `Eq(X)` recipe.

**Run outcome.** A run has three outcomes:

1. **Pass**: every spec passed, and every law obligation was discharged.
2. **Fail**: some spec failed.
3. **Inconclusive**: no spec failed, but some law obligations could not be completed, for example because the recursion limit was reached before a recipe's laws ran, or because a law spec could not be instantiated for lack of a recipe of a type it needs. The report lists the unchecked recipes and the specs that consumed them, as "passed, assuming an unchecked recipe."

Green means pass. How a project treats an inconclusive run, for example in CI, is project policy, not language semantics.

### 10.7 Doubles and recipes

A double is never itself catalogued as a recipe. A recipe may still contain doubles that its construction needed, such as an ordering built by `load_ordering(fs_double, ...)`.

When a recipe is reused in another spec, its doubles keep answering their **stubbed** calls, so the value still works, but their call logs are not checked: expectations belong to the spec that primed them (section 11.2). If a reused recipe calls a contained double with an input that was never stubbed, there is no answer to give; that call invalidates the recipe instead of failing the spec that borrowed it. Blame stays with the recipe's source.

### 10.8 Failure reporting

The runner tracks which recipes each spec used, and groups failures to point at a likely root cause:

- Failures that share a recipe are grouped under that recipe.
- If a law spec for the recipe's type failed on it, that failure is reported first as the likely cause: "``  `Ordering` is reflexive `` failed on the `Ordering(Foo)` from `config file yields ordering`; 7 other failing specs used the same value."
- A spec that fails with some recipes and passes with others points at those recipes. A spec that fails with all of them points at the code under test.

Law specs are scheduled early within each round, without gating anything, so the root cause is usually present in the report.

### 10.9 Declaring laws

A spec is a **law spec** when its title marks one or more interface names in backticks:

```duetto
spec `Ordering` is symmetric {
  ord = every(Ordering(?A)),
  x = some(A),
  y = some(A),
  ensure ord.compare(x, y) == flip(ord.compare(y, x)),
}
```

Rules:

- A backticked name in a title is an **identifier**, not text. It must resolve to a type alias in scope; tooling treats it as code (renaming, go-to-definition). The rest of the title remains free text.
- The marked name is the type constructor. `` `Ordering` `` permits `every(Ordering(X))` for any `X`.
- Each marked name must be bound by **exactly one** `every(...)` in the body. A marked name with no `every`, or with more than one, is a compile error. This may be relaxed later if a law needs several subjects of one interface.
- `every` may appear only in law specs, and only on names marked in the title.
- Any `some` of an interface type in a law spec is assumed lawful. A law relating two interfaces marks both: ``spec `Ordering` agrees with `Eq` { ... }``.

The marker drives the failure reporter (section 10.8) today. In the future, it is what allows a law spec to be read as a logical statement: a schema over every implementation of the marked interfaces, with the lawfulness of the other interface values as hypotheses.

## 11. Scripted doubles

Doubles are a core language feature, not a library, because specs must be writable before any helper framework exists.

- A spec can construct a test value standing in for a dependency.
- The double has an ordinary structural type, typically an exact record of functions.
- The spec **stubs** responses for specific inputs. Entries are comma-separated: `fn(args) returns expr`, or `fn(args) raises raiser(payload)`.
- A call with an input that was not stubbed fails the spec.
- Expected interactions are checked explicitly, with `calls` (section 11.2).

```duetto
spec loading settings works {
  fs = double { read_text("settings.json") returns "{ theme: \"dark\" }" },
  settings = load_settings(fs, "settings.json"),
  ensure settings.theme == "dark",
}
```

Statically, this double contributes `{ read_text: (String) -> String }`.

### 11.1 Doubles for raisers

A double can script an expected failure. This both tests the failure path and contributes the raiser's payload type to the extracted signature.

```duetto
spec missing file is reported {
  fs = double { read_text("a.cfg") raises not_found({ path: "a.cfg" }) },
  ...
}
```

### 11.2 Checking interactions with `calls`

`calls(double.fn)` is a spec-only builtin returning the list of argument records `fn` has received so far. Expectations become ordinary `ensure`s:

```duetto
spec settings are read once {
  fs = double { read_text("settings.json") returns "{ theme: \"dark\" }" },
  settings = load_settings(fs, "settings.json"),
  ensure settings.theme == "dark",
  ensure calls(fs.read_text) == [{ path: "settings.json" }],
}
```

- A call count is `length(calls(...))`; arguments and order can be checked too.
- `calls` accepts only a double **primed by name in the current spec**. Doubles inside recipe values are never reachable by name from a consuming spec, so their expectations are never checked. This rule needs no special case: it follows from scoping.
- There is no implicit "missing interactions fail" rule; required interactions are stated with `ensure`.
- Any `ensure` that mentions `calls` is a trace check. All other `ensure`s are statements about values, which keeps the non-logical parts of a spec syntactically visible.

## 12. Type extraction and production checking

### 12.1 Extraction

Specs fix the signatures of **fields**, the public part of a struct. Locals are private; their types come from local inference. Specs may still call and test locals, but doing so does not fix a local's signature.

Type extraction is constraint-based over spec bodies. Each spec binding has an inferred type, each call to production code constrains argument and result types, and each `ensure` may add constraints.

```duetto
spec greeting works {
  x = greet({ name: "Ada" }),
  ensure x == "Hello, Ada",
}
```

With exact records, this establishes exactly `greet : ({ name: String }) -> String`. Constraints from several specs on the same field are combined by unification, not by searching for a common supertype.

### 12.2 Polymorphism

Type and row variables introduced with `?` in `some(...)` are generalized:

```duetto
spec identity returns its input {
  x = some(?A),
  y = identity(x),
  ensure y == x,
}
```

This contributes `identity : (?A) -> A`, universally quantified over `A`. A spec using `some({ name: String, .. })` contributes an open-record parameter.

**Combining uses.** Each use of a field in a spec yields a **usage type**, in which `?` variables are rigid. The extraction rule is:

> The candidate signature is the least general type of which every usage type is an instance (anti-unification). It is accepted only if each of its type variables comes from a `?` variable in at least one spec; otherwise the specs conflict.

- `(?A) -> A` and `(Int) -> Int` give `(?X) -> X`, accepted: `X` comes from `?A`, and the concrete use is an instance.
- `(Int) -> Int` and `(String) -> String` also give `(?X) -> X`, but `X` comes from no `?` variable, so the specs conflict: "`f` is used at `Int` in spec P and at `String` in spec Q; did you mean `some(?A)`?"

Generalization therefore happens only when a spec asks for it explicitly. The implementation is then checked against the accepted signature.

### 12.3 Labels (proposed)

The set of labels a function accepts is the union of the labels its specs pass to it. Specs calling `f('true)` and `f('false)` give `f : ('true | 'false) -> ...`. Every accepted label then has at least one spec exercising it. `some(Bool)` covers the generative case.

This implicit joining is a **deliberate exception** to the principle that generalization must be explicit (section 12.2): labels are cheap, and a misspelled label is visible in the extracted type. Unions of records are never formed implicitly (section 13.4).

### 12.4 Second-class parameters

A parameter receives a `$` marking when any spec passes it a second-class value. A definition may also declare a parameter `$`, which constrains its own body.

### 12.5 Checking pipeline

1. Collect and elaborate all spec entries.
2. Extract the signatures of fields.
3. Typecheck field definitions against those signatures; infer the types of locals.
4. Execute specs in rounds, admitting each passing spec's recipes to the catalogue, until a fixed point or the recursion limit (section 10.5).
5. Report the run outcome, pass, fail, or inconclusive (section 10.6), with failures grouped by shared recipes and constructors (section 10.8).

An implementation cannot strengthen its required input shape or change its return type beyond what the specs establish. When a check fails, diagnostics should identify which spec contributed each conflicting constraint.

Extracted signatures are printed in the same type syntax, including `?` for type variables, so they can serve as a human-readable interface description.

## 13. Open questions and deferred areas

### 13.1 Open questions

- **Choice data.** Tagged unions are deliberately not adopted while alternatives are explored. The plan is in section 13.4.
- **Evaluation cost.** Re-running specs for each newly catalogued type can grow quickly. The recursion limit may need a companion cap on instantiations per consumer spec, or sampling.
- **Unconstrained results.** If no spec inspects a function's result, its return type is unconstrained.
- **Overloaded `raise`.** A single overloaded raiser, with payloads told apart by a label field, would require intersection types and effectively reintroduce discriminated unions. Named raisers are the current design.
- **Termination.** Reading `some` specs as proofs would require totality of the production functions involved, probably through an opt-in marker. Without it, the logical reading is partial correctness.
- **Exact syntax** for imports, doubles, and comments.

### 13.2 Deferred

- List deconstruction and pattern matching (planned)
- Recursive type aliases (now required by the plan in section 13.4, for trees as `{ value: A, children: [Tree(A)] }`)
- Formal rules for label subtyping and function variance
- Mutable state
- Exact generator semantics for all `some(T)` forms
- Imports, and abstract types in modules. Abstract types will need a way to state whether `==` may see through them.
- An exhaustive formal grammar and operational semantics

### 13.3 Formal core (priority)

The distinctive features interact closely, so a small formal core comes before further syntax work. In order, since each step depends on the previous ones:

1. **Typing and generalization**, including the extraction rule (section 12.2).
2. **Row unification** for open records.
3. **`$` escape checking.**
4. **Initialization order** in structs (section 3.5).
5. **Operational semantics of `try`** and unwinding.

### 13.4 Choice data without tagged unions

Tagged unions are a proven solution, which is exactly why alternatives are explored first. The plan is to introduce **both** of the forms below, paying their costs early, since most of those costs buy features needed anyway.

#### Untagged unions of labels and records

Exact records can be told apart by their field sets, so a union of exact records with different field sets is unambiguous. With width subtyping it would not be.

```duetto
Expr: { num: Int } | { add: { l: Expr, r: Expr } },
Option(A): 'none | { some: A },
Result(A, E): { ok: A } | { err: E },

eval = e -> case e {
  { num } -> num,
  { add } -> eval(add.l) + eval(add.r),
},
```

- A union may contain labels and exact records, as long as every member has a **distinct label or field set**, and **no member is a type variable**. The last condition preserves parametricity: code never tests whether a value is an `A`, only which known shape it has.
- **Members are exact.** A member with an open row, such as `{ name: String, .. }`, would overlap every record with `name`, so it is forbidden.
- **Distinctness is checked after expansion.** Member aliases are flattened first, as in `Option(A) | { y: Int }`, and recursive aliases are unfolded one level. A member that expands to a type variable is excluded.
- Values are plain data: they print well, `some(Expr)` synthesizes them, and `==` works structurally.
- **Projection on a union is an error** for now: `u.name` is rejected even if every member has `name`, since allowing it would amount to width subtyping. The value must go through `case`. This may be revisited.

**Patterns.** A record pattern may be exact or open:

- An exact pattern such as `{ a }` matches only the member whose field set is exactly `{ a }`.
- An open pattern such as `{ a, .. }` matches every member that has the field `a`. The field must have the same type in all the members it matches.
- Branches are checked in order. A branch that is fully covered by earlier branches is an error, as with wildcard patterns elsewhere: `{ a, b }` may not follow `{ a, .. }`. The branches together must cover every member.

**Extraction.** Union formation, like generalization, must be **explicit**. A parameter gets a record union type only when a spec uses that union alias, for example through `some(Expr)` or a literal typed against `Expr`. Otherwise, uses with different record shapes are a conflict, as exact records require; specs calling `greet({ name: "Ada" })` and `greet({ name: "Ada", age: 3 })` are reported, not joined. Labels are the deliberate exception (section 12.3).

When uses are combined, the order is fixed:

1. Within each shape class, uses are anti-unified field by field, under the rule of section 12.2. An open use absorbs the exact uses that have all of its fields: `{ num: 1 }` and `some({ num: Int, .. })` give `{ num: Int, .. }`.
2. The classes are then joined into the declared union.
3. A union that would contain an open member is a conflict.

Because members are distinguished by a label or field set, a union behaves like a finite map from discriminators to member types, which keeps this tractable. Unrestricted unions such as `Int | String`, or overlapping members, have no discriminator to pair by, which is why they remain excluded.

#### Handler-interface `case` sugar

A value can carry its own dispatch: a `match` field taking a record of branches.

```duetto
Expr: { match: ($ { num: (Int) -> ?R, add: (Expr, Expr) -> R }) -> R },

num = n -> { match: $h -> $h.num(n) },
add = (l, r) -> { match: $h -> $h.add(l, r) },

eval = e -> case e {
  num(n) -> n,
  add(l, r) -> eval(l) + eval(r),
},
```

This **record encoding** desugars a handler `case` to calling the value's `match` field: `e.match({ num: n -> n, add: (l, r) -> ... })`. Exhaustiveness comes from exact records, and equality from function equality: `num(1) == num(1)` is `'true`. It suits values defined by behavior, such as streams or visitors.

It requires **rank-2 polymorphism**, since `?R` in `match` must be quantified per call. It also requires **second-class records and `$` in function types** (section 9.5): if a branch calls a raiser, the branch closure is second-class, so the branch record is second-class and `match` must take it as a `$`-parameter. Rank-2 polymorphism alone does not address escape.

**Dispatch is syntactic.** The kind of `case` is determined by its branch form, never by the scrutinee's type: `'lt ->` is a label `case`, `{ num } ->` is an untagged-union `case`, and `num(p) ->` is handler dispatch, through `match` or through a `try` (below). The meaning of a `case` never depends on types extracted from specs.

#### The `try` encoding

A value can instead be a **dispatcher** that receives a `$` record of raisers and calls exactly one:

```duetto
num = n -> $h -> $h.num({ n }),
add = (l, r) -> $h -> $h.add({ l, r }),

eval = e -> try $h { <<e($h) } case {
  num(p) -> p.n,
  add(p) -> eval(p.l) + eval(p.r),
},
```

- **No rank-2 polymorphism.** The dispatcher returns `Never`, and the result arrives through the `try`, so there is no `?R` to quantify. A value's type is `($ { num: ({ n: Int }) -> Never, add: ({ l: Expr, r: Expr }) -> Never }) -> Never`.
- **Branches may use `$` values.** Handler branches are the `try`'s own continuation code, not closures stored in a record, so they can freely use enclosing `$` values.
- It requires **`$` in function types** (section 9.5).
- Raisers take a single payload record, so branches are written `add(p)`. Writing `add(l, r)` would need sugar for destructuring the payload.
- Each match unwinds once, which is a performance question for later, not a semantic one.

#### Supporting features

Each of these pays off beyond choice data:

- **Recursive type aliases**, required by both forms. They are **equi-recursive**: a type is its unfolding, with equality decided on regular trees. Recursion must be **contractive**, passing through a record, list, or function type; `T: T` and `T: T | 'x` are rejected.
- **Rank-2 polymorphism**, required by the **record** encoding only, since `?R` in `match` must be quantified per call; the `try` encoding does not need it. It is also needed for abstract types in modules: a module exposing an abstract type with its operations is an existential, which rank-2 polymorphism encodes. The types come from declared aliases, so this is checking, not inference.
- **Printing functions** in failure messages, by lambda site and captures, matching `==`. The closure returned by `num(1)` prints as `num{ n: 1 }`, and a nested value as `add{ l: num{ n: 1 }, r: num{ n: 2 } }`.
- **Constructor-based generation**, so that function-carrying data such as Scott-encoded trees can be generated randomly. Its rules follow below.

#### Constructor-based generation

Today's recipes are values built by specs, which give specific trees but not random ones. Constructor-based generation builds random values of a type by applying its constructors to synthesized arguments.

- **Selection.** Constructors are **explicitly designated**, never discovered. Treating every catalogued function returning `Expr` as a constructor would include operations under test, such as `simplify: (Expr) -> Expr`: a bug in `simplify` would skew every generated input and misattribute failures.
- **Bounds.** Generation uses a **size** parameter that shrinks at each recursive constructor, independent of the recursion limit, which bounds recipe depth. At least one designated constructor must be non-recursive (the grounding check of section 10.5), and selection is biased toward non-recursive constructors as the size runs out.
- **Prerequisites.** Constructor arguments that are function-carrying need recipes, so generation for a type is available only from the round after those recipes exist. Constructors with `$`-parameters cannot be used.
- **Constructor failures.** A constructor that raises or rejects its synthesized arguments, such as a range with `lo > hi`, **discards the candidate**. This counts as a generation failure attributed to the constructor, not a spec failure.
- **Attribution.** A failing generated value is reported as its construction trace, such as `add{ l: num{ n: 1 }, r: num{ n: 2 } }`, and shrunk by trace. Failures that share a constructor are grouped under it, like recipes (section 10.8).
- **Laws.** Generated values of an interface type go through all applicable law specs, like recipes (section 10.6).

#### Order of work

1. Recursive type aliases
2. Untagged unions of labels and records, with explicit union formation in extraction
3. Function printing in failure messages
4. Constructor-based generation, with designated constructors
5. `$` in function types and second-class records
6. The `try` encoding of handler interfaces, built on step 5
7. Rank-2 polymorphism, together with abstract types in modules
8. The record encoding of handler interfaces, built on steps 5 and 7

#### Deliberate tradeoffs

- Each match in the `try` encoding unwinds once; its cost is a performance question.
- Implicit joining of labels is an intentional exception to explicit generalization (section 12.3).
- Treatment of inconclusive runs (section 10.6) is project policy.
- Function identity restricts the compiler: it may not merge lambda sites or drop captures (section 5.1).

## 14. Examples

### 14.1 Exact structural input

```duetto
greet: person -> "Hello, " + person.name,

spec greeting works {
  x = greet({ name: "Ada" }),
  ensure x == "Hello, Ada",
},
```

Extracted: `greet : ({ name: String }) -> String`.

### 14.2 Open input

```duetto
spec greeting ignores other fields {
  p = some({ name: String, .. }),
  ensure greet(p) == "Hello, " + p.name,
},
```

Extracted: `greet : ({ name: String, .. }) -> String`.

### 14.3 Polymorphic identity

```duetto
identity: x -> x,

spec identity returns its input {
  x = some(?A),
  y = identity(x),
  ensure y == x,
},
```

Extracted: `identity : (?A) -> A`.

### 14.4 Sorting with an explicit ordering

```duetto
sort_by: (xs, ord) -> ...,

spec sorting preserves length {
  xs = some([Int]),
  ord = some(Ordering(Int)),
  ys = sort_by(xs, ord),
  ensure length(ys) == length(xs),
},
```

### 14.5 Failure handling

```duetto
port = try $errs {
  <<parse_int(text, $errs.bad_number)
} case bad_number(e) -> 8080,
```

Here `parse_int` receives a single raiser and cannot store it.

### 14.6 A private helper

```duetto
normalize = s -> trim(lowercase(s)),
same_name: (a, b) -> normalize(a.name) == normalize(b.name),

spec names compare ignoring case {
  ensure same_name({ name: "Ada" }, { name: " ada" }) == 'true,
},
```

`same_name` is a field, so its signature comes from the spec. `normalize` is a local: private, with an inferred type.

## 15. Summary

Duetto is a whole-program language in which specifications are executable code defining what production code may consume and produce, what it must do, and how values can be constructed for further conformance testing. A file is a module is a struct; data is exact records, lists, and labels; choice is expressed by label `case` or by calling closures; failure is a second-class capability passed explicitly; and equality is built in and total. The duet between spec and production code is the reason for the name.
