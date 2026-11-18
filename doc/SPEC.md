# Duetto Language Draft Specification

Nov 9, 2026 · @Alb

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
- Unions are restricted to **struct unions** of labels and exact records, eliminated by an exhaustive `case`.
- **No type-directed dispatch**; closures are the only form of dynamic dispatch.
- `==` is **built-in, total, and non-overridable**; functions compare by definition site plus captured values.
- **Failure is data**: a fallible computation returns a struct union, such as `{ ok: A } | { err: E }` (section 8). Handlers, raisers and second-class `$` values are deferred (section 16).
- **Struct unions**: unions of labels and exact records with distinct field sets, consumed by `case` on their shape (section 9). A union is formed when one spec uses all its shapes (section 12.4).
- **No `type` keyword.** Uppercase entry names bind types, with the same `:` (public) and `=` (private) rule as values.
- `some(T)` synthesizes only **function-free** values; function-carrying values come from a **recipe catalogue**.
- **Law specs** mark interfaces in backticks in their titles and bind each with exactly one `every(...)`.
- Double expectations are explicit `ensure`s over **`calls`**; a spec names the arguments with a projection function when there are several.
- **Operators are not overloaded**: `++` concatenates strings, `+` adds numbers.
- **One spec supplies the signature**: label sets, the fields of record results, and union members are joined only within one spec, and other specs must be included in it. Labels are no longer joined across specs (sections 12.2 to 12.4).
- **A value is catalogued only if its behavior comes from production code**: it is bound in a spec, function-carrying, concrete, and every closure it reaches was written in production code. Values reaching a spec closure or a double are fixtures, so recipes never contain doubles. Recipes are limited by depth, not by rounds, and laws apply to every value usable as their interface.
- **Law specs with no subject are vacuous**, and do not prevent a pass.
- **`ensure` works in any block**, as an assertion checked during whole-program testing and erased in production. Treating an `ensure` that mentions only its function's parameters as a precondition is under design (section 7.1).
- **Specs appear only at file level**, and capabilities originate at the program's entry point, which receives exactly the root capabilities its signature names.

## 2. Design goals

1. **Specs define interfaces.** Public signatures are inferred from spec usage, not from implementations.
2. **Shape and behavior live together.** A spec describes both what a function consumes and produces and what it must do.
3. **Explicit authority.** Access to resources is an explicit value passed to functions, never an ambient power, and the possibility of failure is explicit in a function's result type.
4. **Whole-program spec reuse.** A value constructed in one spec can be catalogued and reused by others.
5. **Effect-free deterministic specs.** Specs are pure, deterministic, and replayable.
6. **Parametricity is preserved.** Code cannot inspect the runtime type of a value, so polymorphic specs test real polymorphic contracts.
7. **Few constructs.** One grouping construct, the brace group, serves as record, block, and module.

## 3. Surface structure

### 3.1 Files, structs, and modules

A Duetto file is the body of a struct: a comma-separated sequence of entries. Every brace group is made of the same entries, so a file, a module, and a record literal are one construct. A file is a module, and importing it yields a record (import syntax is not yet fixed).

That record cannot yet be an ordinary value in every respect. A module's fields may have polymorphic signatures, such as `identity : (?X) -> X`, but record types have no polymorphic fields until rank-2 polymorphism arrives (section 13.4). How imported modules are typed until then, and whether specs in an importing file contribute to a module's signatures, are open questions (section 13.1).

```duetto
Bool: 'true | 'false,

answer: () -> 42,

spec the answer is 42 {
  x = answer(),
  ensure x == 42,
},
```

Entries are separated by commas, and a trailing comma is allowed. Newlines and indentation are not significant.

Source files are UTF-8. Non-ASCII characters may appear only in strings, comments and spec titles, and positions in diagnostics count characters, not bytes.

### 3.2 Entries

This grammar is descriptive, not formal. Operator precedence and associativity are those of the reference parser (`lib/parser.mly`).

```text
File     ::= Entries
Struct   ::= "{" Entries "}"
Entries  ::= (Entry ("," Entry)* ","?)?

Entry    ::= name ":" Expr             -- field
           | Path                      -- punned field or type: { x }, { p.name }, { Bool }, { m.Bool }
           | name "=" Expr             -- local
           | TypeName TypeParams? ":" TypeExpr   -- public type
           | TypeName TypeParams? "=" TypeExpr   -- private type
           | spec SpecTitle Struct     -- file level only (section 7)
           | ensure Expr               -- any block; checked in tests (section 7.1)
           | do Expr                   -- an effect; Expr : {}; not at file level
           | "<<" Expr                 -- block result; last entry; not at file level

Path     ::= (name ".")* (name | TypeName)
```

Here `name` starts with a lowercase letter and `TypeName` with an uppercase letter (section 3.8).

- **Fields** (`name: expr`) are part of the struct's type and value. At file level, they are the module's exports.
- **Locals** (`name = expr`) are visible to later entries but are not part of the struct. At file level, they are private. Types follow the same `:` and `=` rule (section 3.8).
- **Punning** works for paths only: `{ x }` means `{ x: x }`, and `{ p.name }` means `{ name: p.name }`. A path that ends in a type name binds a public type: `{ m.Bool }` means `{ Bool: m.Bool }` (section 3.8).
- **Paths** go through values only. Types are members of records, not of other types, so a type name can only be the last segment: `m.Bool` is a path, but `Bool.x` and `M.Bool` are not.
- **Spec entries** contribute no fields.

**Which entries each kind of brace group allows (decided).** A brace group is a **record** or a **block** (section 3.3), and spec bodies and files have rules of their own:

| Entry | Record | Block | Spec body | File |
| --- | --- | --- | --- | --- |
| field, including a punned one | yes | no | no | yes |
| public type, including a punned one | yes | no | no | yes |
| local | yes | yes | yes | yes |
| private type | yes | yes | yes | yes |
| `ensure` | yes | yes | yes | yes |
| `do` | yes | yes | no | no |
| `<<`, last | no | yes | no | no |
| `spec` | no | no | no | yes |

A **file is a static struct**: it performs no action, so it has no `do`, and it has no result, since a final `<<` would add nothing that more locals could not. Whether a brace group is a record or a block is known only at its closing `}`, so the reference parser checks these rules there, with an error that names the offending entry.

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
Param  ::= Name
```

```duetto
adder = n -> x -> x + n,
sort_by = (xs, ord) -> ...,
map = (xs, f) -> ...,
answer = () -> 42,
```

There is no separate function-definition form. A lambda body extends as far right as possible, ending at a comma, a closing bracket, or the end of its entry. A longer body is a block: `x -> { ..., <<result }`. A lambda is not an operand, so `a + x -> x` is an error, and an operand that is a lambda is written in parentheses, as in `a + (x -> x)`.

### 3.5 Scoping and recursion

The same rule applies in every struct: files, modules, records, and blocks, for fields and locals alike.

- Bindings whose right-hand side is a **lambda literal** form one recursive group. They can refer to themselves and to each other in any order, and their bodies may mention any binding in the struct. The group is a scoping rule only: typing (formal core, section 4.2) and function identity (section 5.1) follow the actual references between its members.
- Every other binding is **computed**, and is visible only to later entries.
- **Initialization order.** For each computed binding `b`, collect the lambdas reachable from `b`'s initializer: those it mentions, then those they mention, transitively. Every computed binding those lambdas mention must come **before** `b`. This guarantees that no computation can read a binding that is not yet initialized.

```duetto
{
  f = make_adder(1),   # computed: backward-only
  g = x -> h(f(x)),    # lambda: may call h, defined later
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

A spec entry is `spec`, a title, and a struct. The title is part of the grammar, not a string literal, so it is never an expression: no `++`, no constants. It is free text up to the opening `{`, under these rules (decided):

- It may contain any character except `{` and `}`. A `}` in a title is an error, which also catches a title whose `{` is missing. Backticks mark the interfaces of a law spec (section 10.9): a **mark** is a type name, optionally after a value path, as in `` `Ordering` `` or `` `m.Ordering` ``, and anything else between backticks, or a backtick that is not closed, is an error.
- It cannot start with `=` or `:`. `spec` is a keyword, so `spec = 1`, `spec: 1` and `f(spec)` are errors that report `spec` used as a name.
- `#` in a title is text, not the start of a comment.
- Brackets need not balance, so a title can describe a half-open range such as `[0, 1)`. Tools should treat a title's text as text, as they treat strings and comments, and its marks as names.
- Titles are shown as written, marks in backticks, in reports and errors.
- Like everything else, it is not sensitive to newlines: every run of whitespace, newlines included, counts as one space, and leading and trailing whitespace is removed.
- It must not be empty.

### 3.7 Comments

A line comment starts with `#` and continues to the end of the line.

The tokens `#!`, `#[`, `]#`, and `#_` are reserved for future use.

### 3.8 Type entries

There is no `type` keyword. **An entry whose name starts with an uppercase letter binds a type**, and its right-hand side is parsed as a type expression. A lowercase name binds a value; labels are marked with `'`. As with values, `:` makes a type public and `=` keeps it private:

```duetto
Bool: 'true | 'false,                                # public type
OrderingResult: 'lt | 'eq | 'gt,
Ordering(A): { compare: (A, A) -> OrderingResult },
Pair = { first: Num, second: Num },                  # private type
```

- Parameters at the head of an entry, as in `Ordering(A): ...`, can only mean a type constructor, since values have no `name(params)` form.
- Punning works for types: `{ Bool }` and `{ m.Bool }` re-export a type from elsewhere.
- **Naming.** Value names, including field names and labels after the `'`, are snake_case: a lowercase letter or `_`, then lowercase letters, digits and `_`, as in `read_file` and `'not_found`. Type names are PascalCase: an uppercase letter, then letters and digits, with no `_`, as in `OrderingResult`. Other spellings, such as `readFile` or `Ordering_Result`, are lexical errors.
- **Keywords.** `case`, `do`, `double`, `ensure`, `every`, `some` and `spec` are reserved and cannot be value names, including field names, locals, parameters and projections. Using one as a name is reported as such, rather than as an unexpected token. Labels are not affected: `'case` is a valid label.

**Type members are transparent and static.** Because a file is a struct and structs are first-class records, public types are members of a record type. For now they are transparent aliases: `m.Bool` is another name for `'true | 'false`, so no dependent typing is needed. Type members exist only at compile time and do not take part in a record's runtime value, its exactness, or `==`. Abstract types, where a type member would become genuinely dependent, are deferred (section 13.2).

## 4. Types

### 4.1 Core type forms

- `Num` and `String`. `Num` is the only number type: an **exact rational number** of any size, as in Scheme, Common Lisp, Julia's `Rational` or Haskell's `Rational`. Arithmetic never rounds and never overflows, so `(1 / 3) * 3 == 1`. Number literals are decimal, with an optional fractional part and exponent, as in `42`, `3.14`, `15e-3` and `2E6`; a literal denotes the exact value it writes, and an exponent implies nothing about floating point. Literals are never negative: unary `-` negates any expression, as in `-1`, `f(-x)` or `-p.age`. It binds tighter than `*`, `/` and `%`, so `-2 * x` is `(-2) * x`, and looser than calls and projection, so `-p.age` is `-(p.age)`. Examples in this draft use whole numbers.
- label singleton types such as `'true`, `'lt`, `'missing`
- unions of labels, such as `'lt | 'eq | 'gt`
- list types `[T]`
- exact record types `{ f1: T1, ..., fn: Tn }`
- open record types `{ f1: T1, .. }` and `{ f1: T1, ..?R }`
- function types `(T1, ..., Tn) -> R`
- the bottom type `Never`, the type of expressions that do not return (such as a raise)
- named type aliases `Name` and `Name(...)`, which may be reached through a path, as in `m.Bool` and `m.Ordering(Num)` (section 3.8)

```duetto
Bool: 'true | 'false,
OrderingResult: 'lt | 'eq | 'gt,
Ordering(A): { compare: (A, A) -> OrderingResult },
```

### 4.2 Labels and label unions

Labels are primitive atomic values and singleton types. Duetto has no primitive `Bool`; booleans are the alias `'true | 'false`.

Unions may contain labels and exact records with distinct field sets: these are struct unions (section 9). A union such as `Num | String` is not allowed. Consuming a label union is done by matching on the label (section 6.3), which is ordinary value inspection, not type inspection. A singleton label type is a subtype of any union containing it.

**A union is the set union of its members (decided).** Members are labels and exact records, which describe themselves, not tagged alternatives, so grouping and order do not matter: `'a | ('b | 'c)`, `('a | 'b) | 'c` and `'c | 'b | 'a` are the same type, and a parenthesised union inside a union is flattened. The rule that members have distinct shapes applies to the flattened members. A **repeated member**, such as `'a | 'a`, or `Bool | 'true` once `Bool` is expanded, is harmless as a set but probably a mistake, so it is reported as a **warning**, not an error. Since repetitions can come from aliases, they are found after aliases are expanded, not by the parser.

There are no tagged constructors. Data that would conventionally be a tagged union is a struct union, whose members are told apart by their field sets (section 9).

### 4.3 Exact records

Records are structural and **exact**: `{ name: String }` is the type of records with exactly the field `name`, and no other. There is no width subtyping. A value of type `{ name: String, age: Num }` cannot be passed where `{ name: String }` is expected; the caller must project the needed fields, or the callee must accept an open record.

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

- In a spec, the scope of a type variable is the enclosing spec. In an extracted signature, it is the whole signature: signatures are prenex.
- Type alias parameters, as in `Ordering(A): ...`, are already in binding position and need no `?`.
- In a type alias, a `?` variable that is not a parameter is quantified **per call**: at the smallest function type that contains all its occurrences. In `match: ({ num: (Num) -> ?R, add: (Expr, Expr) -> R }) -> R`, that is the type of `match`, so each call of `match` chooses its own `R`. This needs rank-2 polymorphism (section 13.4), and the rule is provisional until that step.
- A bare name that does not resolve to a type is an error. A typo such as `Strng` is reported, instead of silently becoming a fresh type variable.

Since production code has no type annotations, `?` appears only in specs, extracted signatures, and type aliases.

### 4.8 No tuples

Duetto has no tuples. Parentheses mean grouping and parameter lists only, and `(x, y) -> ...` is a parameter list, not a tuple pattern.

Tuples could be added cheaply as sugar for records with numeric fields, as in Standard ML, but their main appeal would be unifying them with argument lists, so that every function takes a single argument. The current design has no obstacle to that unification, but the deferred handler design does: it has second-class values, and a tuple holding one would make every argument second-class, so unifying tuples with argument lists would need per-field class (section D9). Adopting tuples now would make handlers harder to add later, for a small benefit. Named records serve better, and cost no more to write:

```duetto
divmod = (a, b) -> { div: a / b, mod: a % b },
```

For generic code, the standard library picks field names once, as in `zip` returning `[{ left: A, right: B }]`.

This decision will be revisited if handlers are permanently dropped, or if a light way is found to give record fields their own class.

## 5. Equality

`==` is a built-in language construct. Its behavior cannot be overridden or customized by user code, and it is defined for every first-class value. Both operands must have the same type.

| Value kind | Equality rule |
| --- | --- |
| `Num`, `String`, labels | equal values |
| Lists | same length and pairwise equal elements |
| Records | same fields and pairwise equal field values |
| Functions | same lambda literal and equal captured values (section 5.1) |

### 5.1 Function equality

Two function values are equal when they originate from the **same lambda literal** and their **captured variables are equal**, compared recursively with `==`. A function is therefore equal only to itself; an identical function written elsewhere is different.

**Identity follows sibling references.** References to members of a lambda's own recursive group (section 3.5) are not captures. Instead, a closure's identity is its lambda site plus the external captures of every group member it can **reach**: itself, the siblings it mentions, the siblings those mention, and so on. These are the members of its strongly connected component and of the components it depends on, as in the formal core's section 4.2. Computing captures per lambda would be wrong, because a group member may reach an external value only through a sibling:

```duetto
make = n -> {
  even = k -> case k == 0 { 'true -> 'true, 'false -> odd(k - 1) },
  odd = k -> case k == n { 'true -> 'false, 'false -> even(k - 1) },
  <<even
},
```

`even` captures nothing from outside its group; only `odd` captures `n`. With per-lambda captures, `make(1) == make(2)` would be `'true` although the two functions behave differently. Since `even` reaches `odd`, both closures' identities include `n`, so they differ.

Using the whole group instead would go too far. In `{ id = x -> x, scale = y -> y * n }`, `id` never reaches `scale`, so `n` is not part of `id`'s identity, and an unrelated sibling cannot change how `id` compares.

**Termination.** Equality always terminates. The captures compared are values from outside the group, so comparing them never re-enters the group. Captured data is acyclic because values are immutable and because the **initialization-order rule** (section 3.5) rejects any path from a computed binding back to itself: no captured value can contain a closure of a group that captures it. This rule is therefore a precondition of equality terminating. Restricting identity to reachable members only removes captures from the comparison, so the argument is unchanged.

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
greet: person -> "Hello, " ++ person.name,
```

Operators have exactly one type each: `+` adds `Num`s and `++` concatenates `String`s. Overloading one operator for both would need its meaning to depend on its operands' types, which is type-directed dispatch (section 6.2).

### 6.1 Closures

Functions are first-class values and may capture variables from their defining scope. There is no separate function-definition form: a function is a lambda bound to a name (section 3.4).

### 6.2 Dispatch

Calling a closure is the only form of dynamic dispatch. Calling `ord.compare(a, b)` runs whichever function the record holds; this is how interfaces, resource handles, and doubles work.

There is **no type-directed dispatch**: no methods looked up by runtime type, no type tests, no runtime overload resolution. Code cannot observe the runtime type of a value. This preserves parametricity, which `some(?A)` relies on (section 7.3).

**Comparisons under an ordering (decided).** There is no built-in `<` that works for some types and not others: a comparison always names the ordering it uses, written before a `?`.

```duetto
ensure lexicographic ? "bar" < "foo",
ensure by_age ? ada <= bob,
```

| Form | Means | Holds when `ord.compare(a, b)` is |
| --- | --- | --- |
| `ord ? a < b` | `a` comes before `b` | `'lt` |
| `ord ? a <= b` | `a` does not come after `b` | `'lt` or `'eq` |
| `ord ? a > b` | `a` comes after `b` | `'gt` |
| `ord ? a >= b` | `a` does not come before `b` | `'gt` or `'eq` |
| `ord ? a ~~ b` | `a` and `b` are equivalent under `ord` | `'eq` |

- **It is sugar for a call**: `ord ? a < b` means `case ord.compare(a, b) { 'lt -> 'true, 'eq -> 'false, 'gt -> 'false }`, and its type is `'true | 'false`. Any value with a field `compare: (A, A) -> 'lt | 'eq | 'gt` can be the ordering, matched by structure, so this is ordinary closure dispatch, not dispatch on types.
- **`~~` is not `==`.** `==` is structural equality, while `~~` is equivalence under an ordering, which can be coarser: a case-insensitive ordering makes `"a"` and `"A"` equivalent but not equal. A distinct symbol keeps the two apart; `~~` was chosen over `=` alone, which would also mean binding, and over a reversed spaceship `>=<`, which would need explaining.
- **Precedence.** The ordering is a primary expression, such as `by_age`, `people.by_name`, `by(key)` or a parenthesised expression. The operands bind as arithmetic does, so `ord ? x + 1 < y` compares `x + 1` with `y`. A comparison is non-associative, at the level of `==`: neither can be an operand of the other or of an arithmetic operator, so `a + ord ? x < y`, `x == ord ? a < b` and `ord ? a == b < c` are errors, and parentheses are needed, as in `a + (ord ? x < y)`.
- **The comparison operators exist only after `?`.** A bare `a < b` is an error that says to name an ordering, as in `ord ? a < b`.
- **Chained comparisons**, such as `ord ? lo <= x < hi`, are not part of the form for now (section 13.1).

### 6.3 Case

Label unions, and struct unions (section 9), are consumed with `case`. It is checked for exhaustiveness against the closed union of the scrutinee's type. Branches are comma-separated; a branch body is an expression or a block.

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

### 6.5 Where capabilities come from

Code never obtains authority ambiently: there are no global file systems, clocks, or loggers, and no import yields one. Real capabilities originate at the program's **entry point**. The runtime calls one designated field, provisionally named `main`, with a record of **root capabilities**, and `main` passes on only what each part of the program needs:

```duetto
main: caps -> run_server(caps.net, caps.log),
```

**The entry point's signature is its authority manifest.** Like any field, `main` needs a spec, and its signature comes from that spec. Records are exact, so a spec that passes a double with only `net` and `log` gives `main` the parameter type `{ net: ..., log: ... }`, which a larger record of every root capability would not match. Rather than making the spec mention every root capability, the runtime adapts to `main`: it builds `main`'s argument with **exactly** the fields that `main`'s signature names, with the types the signature gives them. This applies at every level: a root capability is itself a record of functions, and the runtime builds it with exactly the functions the signature names, so a `net` double that stubs only `listen` gives a `net` with only `listen`. A field the runtime cannot provide, or provides at a different type, is an error when the program is built. So `main`'s extracted signature states exactly which authority the program uses, which fits explicit authority (section 2), and a spec for `main` needs doubles only for the capabilities `main` actually uses.

```duetto
spec main serves on the network and logs {
  net = double { listen(8080) << ... },
  log = double { write("started") << {} },
  ensure main({ net, log }) == ...,
},
```

The entry point's name, the set of root capabilities, and their types are not yet fixed (section 13.1). Specs never receive root capabilities: they are pure, so they use doubles (section 11).

### 6.6 Partial primitives

A primitive that cannot produce a result for some arguments needs a defined meaning, since there are no ambient aborts: failure must be returned as data (section 8). The cases known so far:

- **Division and remainder by zero**, `a / 0` and `a % 0`.
- **Access by position**, such as the first element of an empty list or a character past the end of a string. None of these exists yet: lists are consumed through `fold` and similar total primitives (section 4.5).
- **Parsing**, as in `parse_num`, already returns a union (section 8).

Division is an open question (section 13.1). Non-termination is not failure but divergence, and is discussed under termination (section 13.1).

## 7. Spec language

A spec entry's body is a struct whose entries run in order: locals, private types, and `ensure` statements. A private type can name a type for `some`, as in `NumOrd = Ordering(Num), natural = some(NumOrd)`. Specs are pure and deterministic: they perform no ambient I/O, and interaction with resources goes through explicit values, including scripted doubles (section 11). A spec sees the fields and locals of its enclosing struct.

Spec entries appear only at **file level**, directly in a module's struct. A spec inside a lambda body would see parameters that have no values when the spec runs, and a spec inside a nested record would need that record's fields to have signatures, which only a module's own fields receive (section 12.1).

### 7.1 `ensure`

`ensure` introduces a behavioral obligation. Its expression must evaluate to `'true` or `'false`; `'false` fails the spec. The expressions inside an `ensure` also contribute type constraints.

```duetto
ensure x == 42,
ensure ord.compare(a, b) == 'lt,
```

**Outside specs (decided).** `ensure` may appear in any block, not only in spec bodies: in a function body, in a nested struct, or at file level. There it is an assertion. It is checked whenever whole-program testing evaluates it, and it is **erased in production runs**. Erasing it is safe because expressions are pure: removing an `ensure` cannot change what a program computes, only whether a violated condition is reported. Outside specs, an `ensure` is checked like any other production expression and contributes nothing to extraction.

**Preconditions (under design).** This part is a working proposal, not a decision; its open points are listed in section 13.1. An `ensure` in a lambda's body is a **precondition** of that lambda when its expression mentions only the lambda's own parameters and file-level names, such as other fields. Any other `ensure` outside a spec, one that mentions a local of the body or a name captured from an enclosing lambda, is an **assertion** about the function's own computation:

```duetto
average: xs -> {
  ensure is_empty(xs) == 'false,   # precondition: mentions only xs and a field
  n = length(xs),
  ensure is_zero(n) == 'false,     # assertion: mentions a local
  <<sum(xs) / n
},
```

The rule is syntactic on purpose. In a pure function every local is computed from the parameters, so "depends only on the inputs" would make every `ensure` a precondition; what the rule distinguishes is a statement about the inputs **as given**. The second `ensure` above is therefore an assertion, although it says the same as the first; to make a condition a precondition, state it in terms of the parameters.

The difference is **who is at fault** when the condition is false:

- **A failed precondition blames the caller.** If the caller is a spec and the arguments came from `some`, the generated case is **discarded**, not failed, as with QuickCheck's `==>`. If the spec wrote the arguments itself, the spec fails. If the caller is production code, the failure is reported at the call site, as a bug in the caller.
- **A failed assertion blames the function** that contains it, and is reported there, together with the spec whose run reached it.

A spec all of whose generated cases are discarded has checked nothing, and is reported. How discards interact with law specs is open (section 13.1).

**Inside specs** there are no preconditions. Every `ensure` in a spec, at any depth, including one in the body of a lambda the spec defines as a local helper, is a spec obligation: if it is false, the spec fails.

### 7.2 `some(T)`

`some(T)` is available only in specs and denotes a generated value of type `T`. It has two meanings:

- **Statically**, it contributes type information and is the main bridge between testing and polymorphism.
- **Dynamically**, it produces concrete values using the deterministic, replayable generator system.

Type and row variables are introduced with `?` at their first occurrence (section 4.7).

```duetto
x = some(Num),
xs = some([?A]),
p = some({ name: String, .. }),
```

### 7.3 Abstract types and parametricity

A type variable in a spec has one of two dynamic meanings, decided statically by where it occurs:

- **Opaque**, the default. `some(?A)` generates **opaque tokens**: values that support only `==`, and that belong to no other type. The spec runs as one instantiation, at the token type. Because Duetto has no type-directed dispatch (section 6.2), production code cannot inspect these values.
- **Anchored**, when the variable also occurs inside a function-carrying `some(...)` or `every(...)`, as `A` does in `ord = some(Ordering(?A))`. Values of such a type must come from the recipe catalogue, and no recipe has the token type, so the variable is instead instantiated with the type argument of each catalogued recipe: the spec runs once per `Ordering` recipe, with `A := Foo`, `A := Num`, and so on, and its `some(A)` produces values of that concrete type. When several variables are anchored, the spec runs once per compatible combination of recipes.

Both meanings agree statically: during extraction every `?` variable is rigid (section 12.2), whichever way it is run. Only the cost differs. An opaque spec runs once; an anchored spec runs once per recipe, or per combination, which is what consumer caps (section 10.5) limit.

The guarantee is **parametricity up to equality**. Every Duetto type supports `==`, so "for all `A`" already means "for all `A`, with equality": a function of type `(?A) -> A` must still be the identity, but one of type `(?A, A) -> A` may branch on whether its arguments are equal. To exercise such branches, the generator for abstract types must **produce collisions**, sometimes generating equal values, rather than tokens that are always distinct.

### 7.4 What `some` can synthesize

`some(T)` synthesizes values only for **function-free** types: `Num`, `String`, labels and label unions, and lists and records built from those. Type variables are opaque tokens or anchored, as section 7.3 describes.

A type that contains a function anywhere, transitively, cannot be synthesized. This includes `(Num) -> Num`, `[(Num) -> Num]`, `Ordering(Num)`, and `{ name: String, compare: ... }`. For these, `some(T)` draws a whole value from the **recipe catalogue** (section 10.5), using every admitted recipe that can be used as a `T`. Data fields are never synthesized separately from function fields, since that could break invariants between them.

If no spec could ever construct a recipe for `T`, the compiler reports it: "no spec constructs an `Ordering(Num)`." If one could, but no recipe was admitted in a particular run, the spec is reported as not run, and the run cannot pass (section 10.6). The standard library ships recipes for common cases, such as the natural orderings on `Num` and `String`.

`some` has one meaning everywhere. A law spec checking an ordering and a sorting spec relying on one both draw from the same catalogue, and recipe-derived values are presumed good.

### 7.5 `every` in laws

`every(T)` is a variant of `some` used only in law specs (section 10.9). It binds the implementation **under test**, while any `some` of an interface type in the same spec is assumed lawful. `every` is valid only on function-carrying types; on a function-free type it would mean the same as `some`, so it is a compile error.

### 7.6 Function-free and function-carrying types

The distinction between function-free types (synthesizable by `some`) and function-carrying types (drawn from recipes) is internal to the compiler and test runner. It has no surface syntax: production code never needs to restrict a parameter to synthesizable types.

## 8. Failure as data

A computation that can fail returns a value that says so: a **struct union** (section 9) with one member for success and one for each kind of failure. There are no exceptions, no ambient aborts, and nothing unwinds. The standard library's idiom is a `Result` alias:

```duetto
Result(A, E): { ok: A } | { err: E },

port = case parse_num(text) {
  { ok } -> ok,
  { err } -> 8080,
},
```

Here `parse_num` returns `{ ok: Num } | { err: { text: String } }`. The name `Result` and the field names `ok` and `err` are a library convention, not keywords: any struct union with distinct field sets works the same way, and a function with several kinds of failure can return `{ ok: Config } | { not_found: { path: String } } | { parse_error: { path: String, line: Num } }`.

- **Failure is visible in the type.** A caller cannot use the result without a `case` that covers every member (section 9), so an unhandled failure is a type error.
- **Failure values are plain data.** They print in failure messages, `some` can generate them, `==` compares them, and recipes and laws need no special cases.
- **Explicit authority is unchanged.** Capabilities such as file systems remain explicit values (section 6.5). A capability that can fail returns a union, like any other function.
- **Error translation** is an ordinary `case`: `{ err } -> { err: { path: p, reason: "syntax" } }`.
- **One spec observes both outcomes.** A spec that sees both `parse_num("7") == { ok: 7 }` and `parse_num("x") == { err: { text: "x" } }` gives `parse_num` its union result (section 12.4). Other specs may then test single outcomes.

**Propagation.** Without further sugar, every fallible call needs a `case`, even when the caller only passes the failure on. A propagation form, provisionally written `e?`, would mean "the `ok` value of `e`, or else the enclosing function returns `e`'s failure unchanged". It can be defined without types, since the members it distinguishes are visible by shape. It is deferred (section 13.2): the proof-of-concept compiler is written without it.

**Handlers are deferred.** Earlier revisions handled failure with `try`, handler `case`, and second-class raisers. That design is kept in section 16. It can be added later without breaking programs that return unions.

## 9. Struct unions

A **struct union** is a union of exact records with distinct field sets, possibly together with labels. Exact records can be told apart by their field sets, so such a union is unambiguous; with width subtyping it would not be. There are no tagged constructors: a member's field set is its tag.

```duetto
Expr: { num: Num } | { add: { l: Expr, r: Expr } },
Option(A): 'none | { value: A },
Result(A, E): { ok: A } | { err: E },

eval = e -> case e {
  { num } -> num,
  { add } -> eval(add.l) + eval(add.r),
},
```

- A union may contain labels and exact records, as long as every member has a **distinct label or field set**, and **no member is a type variable**. The last condition preserves parametricity: code never tests whether a value is an `A`, only which known shape it has. A single **rest variable**, standing for the members not otherwise listed, is under consideration (see "Open unions" below); it keeps that guarantee, since code still tests only known shapes.
- **Members are exact.** A member with an open row, such as `{ name: String, .. }`, would overlap every record with `name`, so it is forbidden.
- **Distinctness is checked after expansion.** Member aliases are flattened first, as in `Option(A) | { y: Num }`, and recursive aliases are unfolded one level. A member that expands to a type variable is excluded. Recursive aliases such as `Expr` are needed, so they move from deferred to required (section 13.2).
- Values are plain data: they print well, `some(Expr)` synthesizes them, and `==` works structurally.
- **Projection on a union is an error** for now: `u.name` is rejected even if every member has `name`, since allowing it would amount to width subtyping. The value must go through `case`. This may be revisited.
- **A record is included in every union that contains its shape**, as a label is included in every label set that contains it. So `{ ok: 1 }` can be returned where `{ ok: Num } | { err: String }` is expected, and the branches of a `case` may produce different members of one union.
- **Dispatch on shape is not type-directed dispatch.** A `case` inspects which known shape a value has, as a label `case` inspects which label it is (section 6.2). The kind of `case` is determined by its branch patterns, never by the scrutinee's type.

**Patterns (decided).** `case` branches and the stubs of a double (section 11) use **one pattern language**. A stub is a `case` branch over a function's argument list. The forms are:

- **Literals**: labels, numbers and strings, matched with `==`, as in `'lt` or `"settings.json"`. A number pattern may be negative, as in `-1`; since patterns are not expressions, `-` is allowed only directly before a number.
- **Binders**: a bare name, such as `path` or `other`, matches any value and binds it in the branch's body or the stub's responses.
- **Pinned values**: `^name` matches the value of a name already in scope, compared with `==`, as in `read_text(^config_path)`. Without the `^`, the name would be a new binder that shadows the local. The sigil `^` is provisional.
- **Typed wildcards**: `some(T)` matches every value of `T` and binds nothing. It is how a pattern states a type, which matters for doubles (section 11).
- **Record patterns**: `{ f1: P1, ..., fn: Pn }` matches a record with exactly these fields whose values match the sub-patterns; `{ f1: P1, ..., .. }` is the open form, matching every record that has these fields. A field written alone is punning, as in record literals: `{ num }` means `{ num: num }`, binding the field's value.
- **List patterns** come with list deconstruction (section 13.2).

The rules for branches:

- An exact pattern such as `{ a }` matches only a member whose field set is exactly `{ a }`. An open pattern such as `{ a, .. }` matches every member that has the field `a`; the field must have the same type in all the members it matches.
- Branches are tried in order, and a branch that is fully covered by earlier branches is an error: `{ a, b }` may not follow `{ a, .. }`, and nothing may follow a binder.
- **A `case` must be exhaustive**: its branches together cover every member, which a final binder always does. **A double need not be**: a call that no stub matches fails the spec (section 11).
- Patterns inspect values, never types: a binder or typed wildcard on a value of type `A` matches without testing anything (section 6.2).

Not yet settled (section 13.1): literal patterns on a scrutinee that is not a union, such as `case n { 0 -> ..., n -> ... }` on a `Num`; a form that names and types at once, such as `path @ some(String)`; and patterns in lambda parameters, which are not planned for now, since `case` in the body does the same job.

**Open unions (open).** A union could end with one type variable standing for the rest of its members, so that code can handle some shapes and pass the others through unchanged:

```duetto
map_err: (r, f) -> case r { { err } -> f(err), other -> other },
```

with the signature `map_err : ({ err: ?A } | ?B, (A) -> ?C) -> C | B`. The proposal:

- **A catch-all pattern.** A binder, such as `other`, as the last branch matches every member the earlier branches did not (see "Patterns" above), and has the rest variable's type.
- **Shape constraints.** A rest variable comes with the shapes it must not contain: here, `B` has no member with field set `{ err }`, or the first branch would take values that belong to `B`. This mirrors `R lacks name` for record rows (formal core, section 3). Similarly, the members of `C` and `B` in the result must not share a shape with different types.
- **Errors at instantiation.** A call that instantiates a variable so as to break these constraints, such as `B := { err: String } | 'x`, is a type error reported at that call; the construct itself is allowed.
- **One variable per union in parameter types.** Matching `'x | { err: Num }` against `{ err: ?A } | ?B` has one solution, `B := 'x`, while matching it against `?B | ?C` has many, so there would be no principal type. A union in a parameter type has at most one variable, as a record has at most one row variable. In a result, such as `C | B`, several variables are fine when the parameters already fix them.
- **The same machinery as rows.** Since members have distinct shapes, a union is a finite map from shapes to member types, and a union with a rest variable is an open row over shapes. Unification and lacks constraints then work as for record rows. The same idea appears in OCaml's polymorphic variants and Koka's effect rows.
- **Generators.** `some({ err: ?A } | ?B)` must produce values of `B` that are not of shape `{ err }`, as tokens of an abstract type.

This belongs to the struct-union step (formal core, section 9.3), and is listed in section 13.1.

**Extraction.** How unions are formed from specs is described in section 12.4. Because members are distinguished by a label or field set, a union behaves like a finite map from discriminators to member types, which keeps extraction tractable. Unrestricted unions such as `Num | String`, or overlapping members, have no discriminator to pair by, which is why they remain excluded.

## 10. Interfaces, laws, and recipes

### 10.1 Interfaces as ordinary values

Duetto has no typeclasses or dedicated capability types. Interfaces are ordinary records of functions, passed explicitly:

```duetto
Ordering(A): { compare: (A, A) -> OrderingResult },
Reader: { read_text: (String) -> String },

sort_by: (xs, ord) -> ...,
```

This keeps authority and behavior explicit and works naturally with structural typing. Whether a record represents authority is a property of the runtime model, not a type-system marker.

### 10.2 Shape versus behavior

A value of type `Ordering(A)` has the shape of an ordering, but that does not imply it is transitive or reflexive. Specs keep the two together: shape is extracted from the types used in specs, and behavior is checked by `ensure` in the same specs.

### 10.3 Reusable law specs

The standard library may define generic law specs, such as reflexivity, sign symmetry, and transitivity for `Ordering(A)`. Because a program is compiled and tested as a whole, these law specs are applied to every implementation of the interface that the program's specs bind and whose behavior comes entirely from production code (section 10.5).

> If a program introduces a new implementation of an interface and a spec binds a value of it, generic law specs for that interface are automatically applied to it during whole-program testing, provided the value's behavior comes from production code.

The promise is about production implementations, wherever their container was built: an ordering a spec assembles from a production comparison is checked, and one a spec writes as a stub is not.

This is reusable conformance testing, not a static proof. Section 10.9 describes how law specs are declared.

### 10.4 Spec-derived recipes

Each spec has up to three outputs: type constraints, runtime tests, and **construction recipes**. A recipe is a catalogued description of how a spec deterministically builds a value of some type `T`.

```duetto
spec config file yields ordering {
  fs = double { read_text("config.txt") << "by_name" },
  ada = { name: "Ada" },
  bob = { name: "Bob" },
  ord = load_ordering(fs, "config.txt"),
  ensure ord.compare(ada, bob) == 'lt,
  ensure ord.compare(bob, ada) == 'gt,
  ensure ord.compare(ada, ada) == 'eq,
}
```

This spec can yield a recipe for `Ordering({ name: String })`, which law specs can then reuse, provided `load_ordering` reads the file while it builds the ordering. An ordering that keeps reading through `fs` would still reach the double, so it would not be catalogued (section 10.5).

All three `ensure`s are needed, in this one spec. The ordering's results are labels in a result position, so they contain only the labels one spec observes (section 12.3). With `'lt` alone, `compare` would extract as returning only `'lt`, the implementation would fail its check, and as an `Ordering` it would fail reflexivity.

Coverage extends only to construction paths that some spec describes; it grows as specs become more generative.

### 10.5 The recipe catalogue

**What is catalogued.** Recipes exist to test production implementations (section 10.3). What matters is therefore where a value's **behavior** comes from, not who assembled it. A value is catalogued as a recipe exactly when all of these hold:

1. **It is the value of a spec binding**, `x = e`. Values that are only passed along, as in `sort_by(xs, by_name())`, are not candidates, so a spec decides what it offers to the catalogue by naming it.
2. **It is function-carrying.**
3. **Its behavior comes only from production code.** Every closure reachable from the value, through record fields, list elements, and the captures of closures, has its lambda literal in production code. Function identity (section 5.1) already tracks each closure's lambda site and captures, so the runner can check this by walking the value. A closure written in a spec, including any double, makes the value a **fixture**.
4. **Its type is concrete**: it contains no type variables and no opaque tokens (section 7.3). So binding a polymorphic field, as in `f = identity`, does not produce a recipe, while `add1 = make_adder(1)`, of type `(Num) -> Num`, does.
5. **The spec passed.**

Consequences:

- `ord = { compare: by_name }`, the shape used in section 14.4, is catalogued and checked against the `Ordering` laws: the record is built in the spec, but its only closure, `by_name`, is production code.
- `ord = reversed(stub_ordering)`, where `stub_ordering` is written in the spec, is a fixture, since the result reaches the stub. A spec can therefore test a combinator with a deliberately partial or unlawful stub, or test that `sort_by` survives an inconsistent ordering, without that value being checked against the laws.
- `f = make_lookup(store)`, where `store` is a double, is a fixture, since `f` reaches the double. No recipe ever contains a double, so a recipe reused elsewhere can never call one with an unstubbed input (section 10.7).
- The function under test is not catalogued merely by being mentioned: a spec that calls `sort_by` does not bind it.

A recipe enters the catalogue only after the spec that constructs it **passes**. Recipes are never admitted provisionally. Admission is monotonic: once admitted, a recipe stays in the catalogue.

Specs run in rounds until a fixed point:

1. Statically, each spec **needs** the recipe types of its function-carrying `some(...)` and **produces** the function-carrying values of its bindings. Whether a produced value is catalogued is decided when the spec runs, by the rules above.
2. Round 0 runs the specs that need no recipes. Each passing spec adds its recipes to the catalogue.
3. Each later round runs the specs whose needs are now covered, including earlier specs re-run with newly available types. Passing specs add more recipes.
4. Admission stops when a round admits no new recipe within the **depth limit**.
5. A final pass then runs every law obligation of every admitted recipe that has not run yet (section 10.6). Values that specs bind during the final pass are **not admitted**, since admission has stopped, so the final pass creates no new obligations and terminates.

**The depth limit** bounds a recipe's **depth**, not the number of rounds. A recipe built by a spec that drew no recipes has depth 0; one built by a spec that drew recipes has depth one more than the deepest of them. Recursive constructions such as `lexicographic(ord)`, producing an `Ordering([A])` from an `Ordering(A)`, generate an unbounded family: `Ordering([Num])`, `Ordering([[Num]])`, and so on. The limit stops **admission** only. Recipes beyond it are never admitted, so nothing ever uses them and they create no obligations, while laws still run on everything admitted. Reaching the limit is therefore normal, and does not by itself make a run inconclusive. Since admission is monotonic and bounded by depth, the rounds terminate. A cap on instantiations per consumer spec may also be needed to control cost; caps never apply to law specs (section 10.6).

The same spec may therefore run several times, with different concrete types, at different points.

A spec that can never run is reported. If no spec could construct a recipe it needs, even assuming every spec passes, this is a compile-time error, except for a law spec whose marked interfaces have no producer at all, which is vacuous (section 10.6). In particular, if the only spec constructing an `Ordering(Foo)` itself needs an `Ordering(Foo)`, there is no base case: "no grounded recipe for `Ordering(Foo)`." A spec that could run in principle but got no instantiation in a particular run is handled by the run outcome (section 10.6).

### 10.6 Law specs over catalogued types

Recipes are concrete, such as `Ordering(Foo)`, since values with type variables or opaque tokens in their types are never catalogued (section 10.5), while law specs are generic, such as reflexivity over `Ordering(A)`. Type variables are **anchored** by recipe draws (section 7.3): in `every(Ordering(?A))`, `A` is anchored, so the spec runs once per catalogued `Ordering` recipe, with `A` set to that recipe's type argument, such as `A := Foo`. Its `some(A)` then produces `Foo` values, synthesized if `Foo` is function-free and drawn from recipes otherwise.

Law specs do not gate admission. A recipe used by a sorting spec may also be checked by a law spec in the same round. A broken implementation can therefore cause a small cascade of failures, which section 10.8 addresses.

**Why lawfulness can be assumed.** A recipe is admitted when its constructing spec passes, which does not by itself establish that it satisfies the laws of its interface. The assumption that `some` values of an interface type are lawful is justified at the level of the **whole run**: law specs are instantiated for every catalogued recipe of their type, so a recipe that breaks a law fails that law spec and the run fails. A green run therefore implies that every recipe used passed every applicable law, as far as testing goes. A failing run may contain spurious failures in specs that consumed a broken recipe; the failure reporter (section 10.8) groups them.

**Law obligations.** Every recipe used by any spec, and every **generated interface value** (section 13.4), must be run through all applicable law specs. Several rules make this complete:

- **Caps never apply to law specs.** Instantiation caps (section 10.5) may limit consumer specs only.
- **Applicable laws** are those whose marked interface the value **can be used as**, under the subtyping of label sets and `Never` (formal core, section 3.2). This matches how recipes are drawn: a recipe is drawn for every `some(T)` that it can be used as, so any recipe a spec may receive as a `T` must satisfy `T`'s laws. For example, `{ compare: (Foo, Foo) -> 'lt }` is not exactly an `Ordering(Foo)`, since its result set is smaller, but it can be used as one, so it is drawn for `some(Ordering(Foo))` and the `Ordering` laws apply to it; reflexivity, which requires `'eq`, then fails, as it should. A value of interface type nested inside another value, as in `{ name: String, ord: Ordering(Foo) }`, is neither checked nor assumed lawful.
- **Laws follow structure, not names.** Type aliases expand away, so a law marked with `` `Max` `` applies to every value whose structure is `Max`'s, including values of an alias `Sum` with the same structure. Two interfaces with the same structure but different laws must differ in structure, for example in their field names. Whether to add a nominal form is an open question (section 13.1).
- **Multi-interface laws** are instantiated for every combination of recipes of the marked interfaces with matching type arguments. For `` `Ordering` agrees with `Eq` ``, every `Ordering(X)` recipe is paired with every `Eq(X)` recipe.

**Run outcome.** A run has three outcomes:

1. **Pass**: every non-vacuous spec ran at least once and passed, and every law obligation was discharged.
2. **Fail**: some spec failed.
3. **Inconclusive**: nothing failed, but something did not run: some law obligation could not be completed, for example because a law spec could not be instantiated for lack of a recipe of a type it needs, or some consumer spec got no instantiation at all. The report lists the unchecked recipes and the specs that consumed them, as "passed, assuming an unchecked recipe," and the specs that never ran, as "not run: no admitted recipe of type `T`."

A consumer spec that never ran tested nothing, so it cannot count toward a pass. When it never ran because a recipe it needed came from a spec that failed, the run already fails for that reason.

**Vacuous laws.** A law spec is **vacuous** when no admitted recipe can be used as one of its marked interfaces: it has no subject, so there is nothing for it to check. A vacuous law is exempt from the "ran at least once" rule, and from the compile-time error of section 10.5. This lets the standard library define laws for interfaces that a given program never builds.

The exemption does not hide a gap. A law creates obligations only for recipes, and a recipe that some spec uses is a subject, so the law is then not vacuous. If an implementation exists but is never catalogued, nothing draws it either, so no spec relies on its lawfulness; a consumer spec that needs one is reported as not run. The exemption is the same for laws in user code and in the standard library, but a vacuous law in user code is reported as a **warning**, "no admitted recipe is an `Ordering`; this law checked nothing," since a user who writes a law usually expects it to apply. A law spec with a subject that cannot be instantiated for another reason, such as a missing recipe for a non-subject `some(...)`, is not vacuous, and makes the run inconclusive as before.

Green means pass. How a project treats an inconclusive run, for example in CI, is project policy, not language semantics.

### 10.7 Doubles and recipes

**No recipe contains a double.** A double is written in a spec, so a value that can still reach one is a fixture and is never catalogued (section 10.5). A recipe may still have been **built** with a double: `load_ordering(fs_double, ...)` can read its configuration through the double while it constructs the ordering, and the result is catalogued if the ordering itself no longer refers to `fs`.

This rules out a problem that would otherwise arise. Suppose `f = make_lookup(store)`, where `store = double { get("a") << 1 }`, and `f` calls `store` whenever it is invoked. If `f` were catalogued as a `(String) -> Num`, another spec's `some((String) -> Num)` would call it with a generated string, and the double, which has no stub for other inputs, would have no answer. That spec, and the spec that built `f`, are both correct, so neither should fail, and whether the problem appeared would depend on generated inputs. Not cataloguing values that can reach a double avoids this, with no need for recipes to be invalidated after admission. What is lost is law checking of such values. Their behavior depends on a test script, though, so laws would be testing the script rather than an implementation.

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
- The spec **stubs** responses for specific inputs. Stubs are comma-separated, of the form `fn(args) << response`, and are described below.
- The response is evaluated **at call time**. A failing dependency is stubbed by returning a failure value, such as `{ not_found: { path: "a.cfg" } }` (section 11.1).
- **The stubs of one function share its parameter types, and its result type is the join of their responses.** Responses of different shapes form a struct union (section 9): the double is the spec's own statement of what the dependency can return.
- A call with an input that was not stubbed fails the spec.
- Expected interactions are checked explicitly, with `calls` (section 11.2).

**Stub syntax (decided).** A double's body is a list of stubs, and `double` is a keyword:

```text
Double ::= double "{" Stub ("," Stub)* ","? "}"
Stub   ::= name "(" (Pattern ("," Pattern)*)? ")" ("<<" Expr)+
```

- **`<<` marks the response**, as it marks the value a block produces (section 3.3): `read_text("a.cfg") << "content"` says what the call produces. `<<` is not an operator inside expressions, so a response ends where the next `<<`, `,` or `}` begins.
- **Arguments are patterns** (section 9), one per parameter:
  - A literal, such as `"a.cfg"`, matches with `==`; `^cfg_path` matches the value of a local.
  - A binder, such as `path`, matches anything and names it for the responses: `read_text(path) << { not_found: { path } }`.
  - `some(T)` is a **typed wildcard**: it matches every value of `T`. This is the reading `some` has everywhere, "for every value of `T`" (section 7.2), except that in a stub nothing is generated.
  - A record pattern matches part of an argument, as in `save({ path: "a.cfg", .. })`.
- **Parameter types.** Extraction needs each parameter's type. Literals fix it, as `"a.cfg"` makes the parameter a `String`, and so does a typed wildcard: `some(String)` makes it a `String`, and `some(?A)` makes it generic. A binder fixes nothing, so its type must come from another stub of the same function or from a typed wildcard; otherwise extraction reports the type as not fully constrained (formal core, section 6.4).
- **The first matching stub answers.** Stubs are tried in order, as `case` branches are, so a wildcard or binder stub follows the specific ones. A stub whose arguments are entirely covered by earlier stubs is an error.
- **Repeated calls get successive responses.** A chain `<< r1 << r2 << r3` gives `r1` to the first call the stub answers, `r2` to the second, and so on; each stub counts the calls it answers, so a wildcard stub's chain advances on every call it matches. After the last response, **the last response repeats**, which is also what a single response means. Responses that run out, or that repeat in a cycle, were considered; repeating is what mocking frameworks do, and a spec that needs to rule out extra calls can count them with `calls`.
- **All responses of all stubs of a function** join into its result type, so a chain may mix shapes:

```duetto
spec fetching retries after timeouts {
  net = double {
    fetch("a") << 'timeout << 'timeout << { ok: "data" },
    fetch(some(String)) << 'unreachable,
  },
  ensure fetch_with_retry(net, "a") == { ok: "data" },
  ensure length(calls(net.fetch)) == 3,
},
```

Here `net`'s type is `{ fetch: (String) -> 'timeout | 'unreachable | { ok: String } }`.

A response can use the arguments its stub's binders matched, as in `read_text(path) << { not_found: { path } }` after a `read_text("ok.cfg") << { ok: "content" }` stub that fixes the parameter's type.

```duetto
spec loading settings works {
  fs = double { read_text("settings.json") << "{ theme: \"dark\" }" },
  settings = load_settings(fs, "settings.json"),
  ensure settings.theme == "dark",
}
```

Statically, this double contributes `{ read_text: (String) -> String }`.

### 11.1 Testing failure paths

A dependency that can fail returns a struct union (section 8), so a double for it returns failure values from some stubs:

```duetto
read_file: (fs, path) -> case fs.read_text(path) {
  { ok } -> { ok },
  { not_found } -> { err: "missing: " ++ not_found.path },
},

spec read_file returns content or reports a missing file {
  fs = double {
    read_text("ok.cfg") << { ok: "content" },
    read_text("a.cfg") << { not_found: { path: "a.cfg" } },
  },
  ensure read_file(fs, "ok.cfg") == { ok: "content" },
  ensure read_file(fs, "a.cfg") == { err: "missing: a.cfg" },
},
```

Extracted: `read_file : ({ read_text: (String) -> { ok: String } | { not_found: { path: String } } }, String) -> { ok: String } | { err: String }`.

- The double's type comes from its stubs: `read_text`'s result is the join of its two responses.
- `read_file`'s result is a union because this one spec observes both shapes (section 12.4). Further specs may observe only one of them.
- **Both stubs belong in one double.** The double is a parameter of `read_file`, a negative position, where different shapes conflict. Two specs whose doubles each stubbed only one outcome would give `read_file` two different parameter types.

### 11.2 Checking interactions with `calls`

`calls` is a spec-only builtin that returns one entry per call a double's function has received so far, in order. Expectations become ordinary `ensure`s:

```duetto
spec settings are read once {
  fs = double { read_text("settings.json") << "{ theme: \"dark\" }" },
  settings = load_settings(fs, "settings.json"),
  ensure settings.theme == "dark",
  ensure calls(fs.read_text) == ["settings.json"],
}
```

**Shape of a recorded call.**

- `calls(d.fn)`, for a function with exactly one parameter, is the list of its arguments, as above.
- `calls(d.fn, (x1, ..., xk) -> e)`, for any number of parameters, passes each call's arguments, in order, to the given function and lists the results. The spec chooses the names, for example `calls(log.write, (level, text) -> { level, text })`.

Function parameters have no names, so no field names are invented for them, and no tuple is needed (section 4.8).

- A call count is `length(calls(...))`; arguments and order can be checked too.
- `calls` accepts only a double **primed by name in the current spec**. Recipes never contain doubles (section 10.7), so no spec can observe the calls made to another spec's double.
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

With exact records, this establishes exactly `greet : ({ name: String }) -> String`. When several specs use the same field, the signature is taken from the **most general** use, and every other use must be compatible with it (section 12.2); different record shapes are never merged into a common supertype.

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

> **One spec supplies the signature.** The signature is one usage type with its `?` variables generalized. Its label sets, the fields of its record results, and its unions are joined over the uses **in that one spec** (sections 12.3 and 12.4). Every other use, in that spec or in others, must be compatible with it: for labels, fields, and union members, that means they must already be included. If no use qualifies, the specs conflict.

- `(?A) -> A` and `(Num) -> Num` give `(?X) -> X`: the concrete use is an instance of the generic one.
- `(Num) -> Num` and `(String) -> String` conflict: neither is an instance of the other. "`f` is used at `Num` in spec P and at `String` in spec Q; did you mean `some(?A)`?"
- `(?A, A) -> A` and `(Num, String) -> Num` conflict: the concrete use contradicts the relationship stated by the generic spec. Only a spec that states the more general contract, such as `(?A, ?B) -> A`, can relax it.
- `(?A, Num) -> A` and `(Num, ?B) -> Num` conflict: each is generic in a different parameter, and no spec states the combined claim.

The signature is therefore always exactly what one spec wrote, and generalization happens only when a spec asks for it explicitly. After extraction, every spec is re-typed against the signatures, and the implementation is checked against them. The formal rules, including when an element type seen only as an empty list defaults to `Never`, are in the separate formal core document.

### 12.3 Labels

The set of labels a function accepts is the union of the labels **one spec** passes to it. A spec calling both `f('true)` and `f('false)` gives `f : ('true | 'false) -> ...`; other specs may then pass either label. `some(Bool)` covers the generative case. Every accepted label then has a spec exercising it, and one spec exercises the whole choice.

The same holds for results: a function may return only labels that one spec **observes**, by comparing the result with it, or **handles**, in a `case` on the result. This is deliberate: every label of a public interface is exercised, and one spec sees them all. It applies to every predicate, since `==` can produce both `'true` and `'false`: a predicate needs a spec that observes both, which can be as short as `ensure [is_even(2), is_even(3)] == ['true, 'false]` (section 14.6). Specs that observe `'true` and `'false` separately, with no spec that observes both, conflict: "spec P observes `'true` and spec Q observes `'false` at the result of `is_even`; one spec must observe both."

Record results follow the same principle: when a spec projects fields from a result, the result's type consists of exactly the fields that spec observed (section 12.4), and an implementation that returns more fails its check.

It applies in the same way to **fields that return interface values**, such as a function returning an `Ordering`: the labels returned by the interface's functions are result labels too. One spec for such a field must observe or handle every label the interface returns, for example all three results of `compare` (section 10.4). Otherwise the extracted type has a smaller label set than the interface, and the value is checked against the interface's laws anyway, since it can be used as one (section 10.6). A `case` that handles every label is the most compact way to do this.

Joining within one spec is not generalization: it adds no type variables. An earlier rule joined labels across all specs, as an exception to "a signature is what one spec wrote". It was dropped so that labels, record fields, and union members follow one rule (section 12.4).

### 12.4 Rows and unions

**Record results are joined within a spec.** A spec that projects fields from a result, such as `settings.theme`, observes only those fields. Each such use is open: it says the result has at least these fields. At a positive position, such as a result, the signature's record consists of the fields observed by the uses of **one spec**, and it is exact. If one of that spec's uses observes the whole record, for example by comparing it with a record literal, its other uses must observe a subset of those fields. Uses in other specs must observe a subset too. So these specs are accepted together:

```duetto
spec settings have a theme {
  settings = load_settings(fs, "a"),
  ensure settings.theme == "dark",
},

spec settings are complete {
  ensure load_settings(fs, "b") == { theme: "dark", size: 3 },
},
```

and give the result type `{ theme: String, size: Num }`, taken from the second spec, which the first is included in. Likewise `ensure divmod(7, 2).div == 3` and `ensure divmod(7, 2).mod == 1`, in one spec, give `{ div: Num, mod: Num }`, whether or not the spec names the result. In two separate specs they conflict, since neither spec's fields include the other's. This is the record counterpart of the label rule of section 12.3: a result contains exactly what one spec observes, so an implementation that returns a field no spec observes fails its check. The formal core states it in its sections 6.2 and 6.4.

At a negative position, such as a parameter, open uses stay wildcards, and different exact shapes in separate specs conflict: `greet({ name: "Ada" })` in one spec and `greet({ name: "Ada", age: 3 })` in another are reported.

**When are unions formed? (decided)** Uses that see a value in different shapes, as in `parse_num("7") == { ok: 7 }` and `parse_num("x") == { err: { text: "x" } }`, form a union when they are **in one spec**, at any position, as labels do:

- At a result, one spec observes every member shape, by comparing results with records of each shape, or by a `case` that handles each shape.
- At a parameter, one spec passes every member shape, or states the union with `some`, written inline as in `some({ ok: String } | { err: String })` or through an alias such as `some(Result(String, String))`. One double whose stubs return different shapes also states a union (section 11).

Other specs may then use single members, since a record is included in every union that contains its shape (section 9). Shapes seen only in separate specs, with no spec that sees them together, conflict. When forming a union, the uses of one shape are first combined by the record rules above, and a union that would contain an open member is a conflict.

A mistaken shape within one spec, such as `greet({ name: "Ada" })` next to `greet({ name: "Ada", age: 3 })`, now forms a union instead of a conflict. It is still reported: an implementation that projects `p.name` fails its check, since unions have no projection (section 9), and one that handles both shapes is what that spec asked for.

Three other rules were considered. Joining shapes across specs only at positive positions, and forming parameter unions only through `some`, kept parameters strict but needed two rules, one for labels and one for shapes. Forming unions **only explicitly**, through `some`, cannot express a union result, since `some` does not apply to results. Joining distinct shapes across specs **everywhere** would let one spec widen another's parameters silently, the mistake exact records exist to catch.

### 12.5 Checking pipeline

1. Collect and elaborate all spec entries.
2. Extract the signatures of fields.
3. Re-type every spec against the extracted signatures. This is the soundness step: each use of a field may be compatible with its signature on its own while a spec that combines several uses is ill-typed.
4. Typecheck field definitions against those signatures; infer the types of locals.
5. Execute specs in rounds, admitting each passing spec's recipes to the catalogue, until no new recipe is admitted within the depth limit, then run the remaining law obligations (section 10.5).
6. Report the run outcome, pass, fail, or inconclusive (section 10.6), with failures grouped by shared recipes and constructors (section 10.8).

Steps 1–4 are specified precisely in the formal core document, section 7.4.

An implementation cannot strengthen its required input shape or change its return type beyond what the specs establish. When a check fails, diagnostics should identify which spec contributed each conflicting constraint.

Extracted signatures are printed in the same type syntax, including `?` for type variables, so they can serve as a human-readable interface description.

## 13. Open questions and deferred areas

### 13.1 Open questions

- **Choice data.** Tagged unions are not adopted. Struct unions (section 9) take their place, and section 13.4 plans the rest.
- **Open unions** (section 9). Unions ending with one rest variable, as in `map_err : ({ err: ?A } | ?B, (A) -> ?C) -> C | B`. Recommendation: allow them, with a catch-all binder pattern as the last `case` branch, shape constraints on the rest variable checked at each instantiation, and at most one variable per union in parameter types. A final binder is also allowed on unions without a rest variable, where it covers the remaining members (section 9). Open point: how extraction forms a rest variable from specs.
- **Preconditions** (section 7.1). The whole precondition rule is under design: the syntactic test, the blame rules, and discarding. The two items below are open points within it.
- **Preconditions in law specs** (section 7.1). An implementation could escape a law by a precondition that rejects the summoned values the law is checked with. The options: (1) discard as in other specs, and report a law spec whose cases were all discarded, as for any spec; (2) also report every discard in a law spec, since a law should hold for every value of the interface's type; (3) treat a precondition that fails in a law spec as a failure of the law. Recommendation: (1) for now, since it is the general rule, with discard counts shown in the report so that a law checked mostly on rejected inputs is visible.
- **Generating inputs that satisfy preconditions.** Discarding wastes generated cases when a precondition rejects most of them. A later step could use preconditions to guide `some` (section 7.4).
- **Evaluation cost.** Re-running specs for each newly catalogued type can grow quickly. The depth limit may need a companion cap on instantiations per consumer spec, or sampling.
- **Division by zero** (section 6.6). The options:
  1. **Total arithmetic**: `a / 0 = 0` and `a % 0 = a`, as in Lean and Pony. `/` stays an ordinary operator, but a missing check silently gives a wrong number.
  2. **Division returns a union**: `a / b : { ok: Num } | { div_by_zero: {} }`. Honest, consistent with section 8, but every arithmetic expression then needs a `case` or propagation.
  3. **Both**: total `/` and `%`, plus functions `div` and `mod` in the standard library that return a union, for code that must not divide by zero silently.

  Recommendation: option 3. It keeps arithmetic readable and makes the checked form one call away. `Num` is an exact rational (section 4.1), so overflow does not arise.
- **Remainder on fractions.** `%` on numbers that are not whole needs a definition. The options: **floored**, `a % b = a - b * floor(a / b)`, whose result has the sign of `b`, as in Python and Haskell's `mod`; **truncated**, whose result has the sign of `a`, as in C and Java; or `%` **only on whole numbers**, which needs a whole-number check that the type system cannot express. Recommendation: floored, since it makes `a % b` lie in `[0, b)` for positive `b`, which is what modular code expects.
- **Showing numbers.** A value such as `1 / 3` has no finite decimal expansion, so converting a `Num` to text needs a rule: a fraction such as `1/3`, a repeating decimal such as `0.(3)`, or rounding to a requested number of digits. This is a library question, not a language one.
- **Laws on structurally equal interfaces** (section 10.6). Laws follow structure, so `Max` and `Sum`, both `{ combine: (A, A) -> A }`, share laws, and a law that holds only for `Max`, such as idempotence, fails on every `Sum`. The options:
  1. **Structural discipline**: interfaces with different laws must differ in structure, for example `{ max: ... }` and `{ sum: ... }`. No new construct, but generic code over every such interface needs a common field name, which this rules out.
  2. **Nominal interfaces**: a form that makes an alias a distinct type, so laws attach to its name. Precise, but it is a new construct, and it brings nominal typing into a structural language.
  3. **Abstract types from modules**: a module exporting `Max` as an abstract type gives it a distinct identity. This reuses a feature that is planned anyway (section 13.2), but it is not available until then.

  Recommendation: option 1 now, as the documented rule, and option 3 when abstract types arrive. Option 2 adds the most and should wait until 1 and 3 prove insufficient.
- **Typing imported modules** (section 3.1). Until rank-2 polymorphism, a module's polymorphic fields cannot be fields of a record type. The options:
  1. **Static modules**: an import binds a module name, and `M.f` instantiates `f`'s signature at each use, as with ML structures. A module used as a first-class value, for example passed to a function, may then have only monomorphic fields.
  2. **Polymorphic record fields now**: allow `∀` in record field types, which is rank-2 polymorphism at fields, pulling step 7 of section 13.4 forward.
  3. **Monomorphic exports**: rejected, since even `identity` could not be exported.

  Recommendation: option 1. It costs nothing now and option 2 can later lift its restriction.
- **Specs in importing files** (section 3.1). The options:
  1. **Module-local signatures**: a module's signatures come only from its own specs. Specs elsewhere use its fields as ordinary instances of fixed signatures, and still run as tests, produce recipes, and are subject to laws across the whole program.
  2. **Whole-program signatures**: specs anywhere contribute. This fits the whole-program model, but an importer's spec could widen a library's signature, for example by adding a label, which makes a library's interface depend on its users.

  Recommendation: option 1, so a module's interface is stable and can be read from the module alone.
- **Root capabilities** (section 6.5). The runtime passes `main` exactly the fields its signature names, so the signature is decided. Not fixed: the entry point's name, the set of root capabilities the runtime can provide, and their types.
- **Handlers** (section 16). Whether and when to bring back `try`, handler `case`, and second-class values. They can be added without breaking programs that return unions, but they would give the language two idioms for failure.
- **Label sets shared between field checks** (formal core, section 9.2).
- **Termination.** Reading `some` specs as proofs would require totality of the production functions involved, probably through an opt-in marker. Without it, the logical reading is partial correctness.
- **Exact syntax** for imports.
- **Chained comparisons** (section 6.2). `ord ? lo <= x < hi`, as in Python, would make range checks read naturally. The grammar of comparisons should leave room for it.
- **Patterns** (section 9). One pattern language serves `case` and doubles; the sigil `^` for pinned values is provisional. Open: literal patterns on a scrutinee that is not a union (recommendation: allow them, since they inspect values, and a final binder keeps the `case` exhaustive); a form that names and types at once, such as `path @ some(String)` (recommendation: defer until a stub needs it, since another stub or a typed wildcard usually fixes a binder's type); and patterns in lambda parameters (not planned for now).

### 13.2 Deferred

- List deconstruction and list patterns (planned; the pattern language is in section 9)
- Mutable state
- Exact generator semantics for all `some(T)` forms
- Imports, and abstract types in modules. Abstract types will need a way to state whether `==` may see through them.
- An exhaustive formal grammar and operational semantics
- **Propagation sugar** (section 8), provisionally `e?`: the `ok` value of `e`, or else the nearest enclosing lambda returns `e`'s failure. Deferred until after the proof-of-concept compiler. Open then: which members count as failure (a fixed `ok` convention, or any union with an `ok` member), and how the enclosing function's result union is formed.

### 13.3 Formal core (priority)

The distinctive features interact closely, so a small formal core comes before further syntax work. In order, since each step depends on the previous ones:

1. **Typing and generalization**, including the extraction rule (section 12.2). *Done*, in the separate formal core document, which also covers label subtyping and variance.
2. **Row unification** for open records. *Done*, in the same document.
3. **Struct unions** (section 9), with recursive type aliases, union formation in extraction (section 12.4, decided), and `case` on shapes. This replaces the former `$` and `try` steps, which are deferred with handlers (section 16).
4. **Initialization order** in structs (section 3.5).

### 13.4 Choice data: the plan

Struct unions (section 9) are the language's form of choice data, in place of tagged unions. A second form, values that carry their own dispatch through a `match` field, was planned alongside them; it is deferred with handlers (section D13.4), since its useful variants depend on second-class values. The features below support struct unions.

#### Supporting features

Each of these pays off beyond choice data:

- **Recursive type aliases**, required by struct unions such as `Expr`. They are **equi-recursive**: a type is its unfolding, with equality decided on regular trees. Recursion must be **contractive**, passing through a record, list, or function type; `T: T` and `T: T | 'x` are rejected.
- **Rank-2 polymorphism**, needed for abstract types in modules and for the deferred handler-interface encodings (section D13.4): a module exposing an abstract type with its operations is an existential, which rank-2 polymorphism encodes. The types come from declared aliases, so this is checking, not inference.
- **Printing functions** in failure messages, by lambda site and captures, matching `==`. The closure returned by `num(1)` prints as `num{ n: 1 }`, and a nested value as `add{ l: num{ n: 1 }, r: num{ n: 2 } }`.
- **Constructor-based generation**, so that function-carrying data such as Scott-encoded trees can be generated randomly. Its rules follow below.

#### Constructor-based generation

Today's recipes are values built by specs, which give specific trees but not random ones. Constructor-based generation builds random values of a type by applying its constructors to synthesized arguments.

- **Selection.** Constructors are **explicitly designated**, never discovered. Treating every catalogued function returning `Expr` as a constructor would include operations under test, such as `simplify: (Expr) -> Expr`: a bug in `simplify` would skew every generated input and misattribute failures.
- **Bounds.** Generation uses a **size** parameter that shrinks at each recursive constructor, independent of the depth limit, which bounds recipe depth (section 10.5). At least one designated constructor must be non-recursive (the grounding check of section 10.5), and selection is biased toward non-recursive constructors as the size runs out.
- **Prerequisites.** Constructor arguments that are function-carrying need recipes, so generation for a type is available only from the round after those recipes exist.
- **Constructor failures.** A constructor that returns a failure for its synthesized arguments, such as a range with `lo > hi`, **discards the candidate**. This counts as a generation failure attributed to the constructor, not a spec failure.
- **Attribution.** A failing generated value is reported as its construction trace, such as `add{ l: num{ n: 1 }, r: num{ n: 2 } }`, and shrunk by trace. Failures that share a constructor are grouped under it, like recipes (section 10.8).
- **Laws.** Generated values of an interface type go through all applicable law specs, like recipes (section 10.6).

#### Order of work

1. Recursive type aliases
2. Struct unions, with union formation within one spec in extraction (section 12.4)
3. Function printing in failure messages
4. Constructor-based generation, with designated constructors
5. Rank-2 polymorphism, together with abstract types in modules

The handler-interface encodings, and handlers themselves, are deferred (section 16).

#### Deliberate tradeoffs

- Implicit joining of labels is an intentional exception to explicit generalization (section 12.3).
- Treatment of inconclusive runs (section 10.6) is project policy.
- Function identity restricts the compiler: it may not merge lambda sites or drop captures (section 5.1).

## 14. Examples

### 14.1 Exact structural input

```duetto
greet: person -> "Hello, " ++ person.name,

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
  ensure greet(p) == "Hello, " ++ p.name,
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
  xs = some([Num]),
  ord = some(Ordering(Num)),
  ys = sort_by(xs, ord),
  ensure length(ys) == length(xs),
},

spec sorting puts numbers in order {
  ord = { compare: int_compare },
  ensure sort_by([3, 1, 2], ord) == [1, 2, 3],
},
```

Extracted: `sort_by : ([Num], Ordering(Num)) -> [Num]`, from the second spec, which is the most general fully constrained use. The first spec alone would not be enough: it passes the result only to `length`, so the result's elements are unconstrained, and extraction would report "the most general use of `sort_by` does not constrain its result" rather than guess. Here `int_compare` stands for a standard library comparison on `Num`; the name is provisional.

### 14.5 Failure handling

```duetto
port = case parse_num(text) {
  { ok } -> ok,
  { err } -> 8080,
},
```

Here `parse_num` returns `{ ok: Num } | { err: { text: String } }`, and the `case` must cover both members.

### 14.6 A private helper

```duetto
normalize = s -> trim(lowercase(s)),
same_name: (a, b) -> normalize(a.name) == normalize(b.name),

spec names compare ignoring case {
  ensure same_name({ name: "Ada" }, { name: " ada" }) == 'true,
  ensure same_name({ name: "Ada" }, { name: "Grace" }) == 'false,
},
```

`same_name` is a field, so its signature comes from the spec: `({ name: String }, { name: String }) -> 'true | 'false`. Both `ensure`s are needed, in one spec. A result's label set contains only labels that one spec observes (section 12.3), and the body's `==` can produce both `'true` and `'false`, so a spec that only ever saw `'true` would make the implementation fail its check. `normalize` is a local: private, with an inferred type.

## 15. Summary

Duetto is a whole-program language in which specifications are executable code defining what production code may consume and produce, what it must do, and how values can be constructed for further conformance testing. A file is a module is a struct; data is exact records, lists, and labels; choice is expressed by `case` on labels and struct unions, or by calling closures; failure is data, returned in a struct union; and equality is built in and total. The duet between spec and production code is the reason for the name.

## 16. Deferred

See [Deferred.md](Deferred.md).
