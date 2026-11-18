# Deferred Items: handlers and second-class values

This appendix preserves the design of failure handlers (`try` with handler `case`), raisers, and second-class `$` values, which earlier revisions made part of the language. They were removed from the current design in favor of failure as data (section 8) and struct unions (section 9), because most of their complexity existed to handle failure without unions. They can be added back later without breaking programs that return unions.

The text is kept as it stood when removed, with its sections renamed: former section 8 is D8, former 9 is D9, former 12.4 and 12.6 are D12.4 and D12.6, and the handler encodings of former section 13.4 are D13.4. The parts of former sections 3.5, 11 and 11.1 that concerned `$` and raisers are D3.5, D11 and D11.1. References inside the appendix use these names; references to other sections may describe rules that have since changed. Cases T1–T10 of the formal core's section 9.3 belong to this appendix.

### D3.5 `$`-locals in recursive groups

From former section 3.5: a `$`-local bound to a lambda literal, such as `$go = x -> ...`, belongs to the recursive group too, so a helper that uses a raiser can be recursive. A sibling that mentions it counts as capturing a `$`-name, so that sibling must also be a `$`-local (section D9.1). Mentioning a sibling counts as capturing it for this rule, although it does not count as a capture for function identity (section 5.1): identity only concerns first-class closures, while this rule keeps a first-class closure from holding a second-class one.

### D8. Failure as a capability

The ability to fail is an explicit value, like a filesystem handle. A function can abort only if it was given a raiser. There are no ambient exceptions.

#### D8.1 Concepts

1. `try` introduces a **failure capability**: a record of raisers, bound to a `$`-name. Its body is a block.
2. A `case` directly after the `try` block lists the **handler branches**. Each branch defines **one raiser** of that record, together with the expression or block that runs when it is called.
3. Calling a raiser **unwinds** to its `try` and runs the matching branch. The value of that branch becomes the value of the `try` expression; if no raiser is called, the value is the block's result.

```duetto
config = try $errs {
  text = read_file(fs, path, $errs.not_found),
  <<parse_config(text, path, $errs.parse_error)
} case {
  not_found(e) -> default_config(),
  parse_error(e) -> log_and_default(log, e.path, e.line),
}
```

Logging is authority too, so `log_and_default` receives a `log` capability explicitly, like `fs` (section 6.5).

As with any `case`, the braces may be omitted when there is exactly one branch:

```duetto
port = try $errs {
  <<parse_num(text, $errs.bad_number)
} case bad_number(e) -> 8080,
```

There is no ambiguity with a label `case`. A label `case` has a scrutinee (`case r { ... }`), while a handler `case` follows a `try` block directly; since Duetto has no juxtaposition application, a `case` in that position can only be the handler clause. The branch shapes also differ: labels (`'lt -> ...`) versus raisers (`not_found(e) -> ...`).

#### D8.2 Types

In the example, `$errs` has the exact record type:

```text
{ not_found:   ({ path: String }) -> Never,
  parse_error: ({ path: String, line: Num }) -> Never }
```

- Each raiser returns `Never`, so a raise can appear in any expression position.
- Each error kind has its own exactly typed payload record. The raiser's name acts as the tag, so no tagged values exist as data. A payload whose fields are not fixed by anything else consists of the fields its handler uses (section D12.6).
- **Handler branches define; label branches cover.** In a label `case`, the branches must cover the scrutinee's type. In a handler `case`, the branches *create* the capability's type: there is nothing to check for exhaustiveness, but using `$errs.foo` with no `foo(e)` branch is an error ("no handler for `foo`").
- A branch such as `not_found(e)` resembles a constructor pattern, but Duetto has no tagged variants: it reads as "the `not_found` raiser was called with `e`." Once patterns exist, the payload may be destructured in place: `parse_error({ path, line }) -> ...`.

#### D8.3 Passing narrow capabilities

Because records are exact, a function that can fail in only one way should receive a single raiser, as in `read_file(fs, path, $errs.not_found)`. This is the recommended style: each call shows exactly how it may fail, and specs extract a small exact type. When a function needs several raisers, it receives them individually, or as an open record (`{ not_found: ..., .. }`).

#### D8.4 Error translation

A handler branch may call a raiser from an enclosing `try`, which rewraps errors across layers:

```duetto
parse_error(e) -> $app_errs.bad_config({ path: e.path, line: e.line, reason: "syntax" }),
```

#### D8.5 Higher-order code

Higher-order functions need no effect annotations. A callback that may fail captures a raiser; the function receiving it takes a `$`-parameter (section D9) and stays an ordinary parametric function.

```duetto
values = try $errs {
  <<map(lines, line -> parse_num(line, $errs.bad_number))
} case bad_number(e) -> [],
```

### D9. Second-class values: the `$` sigil

Some values must not outlive the scope that created them. A raiser called after its `try` has returned would have nowhere to unwind to. Duetto marks such values with the `$` sigil and checks the restriction statically, so a developer sees at every use site that a value is special.

#### D9.1 Rules

1. Only `$`-locals, `$`-parameters, and second-class records (section D9.5) can hold second-class values. `$`-names are introduced by `try`, by `$`-locals, and by `$`-parameters. Fields of an ordinary record can never hold them.
2. **Second-class expressions** are exactly these:
   - a `$`-name;
   - a **path** rooted at one, such as `$errs.not_found` or `$h.config`, whatever the type of the projected field;
   - a lambda that captures a `$`-name;
   - a record literal with a second-class field (section D9.5);
   - a block or label `case` whose result is a second-class expression.

   Every other expression is first-class. In particular, **the result of a call is always first-class**, even when the callee is second-class: since rule 3 forbids returning second-class values, no call can produce one. So `map` can collect the results of `$f(x)`, and `$h -> $h.num(n)` may return the value of `$h.num(n)`.
3. A second-class value can be called, projected, bound to another `$`-local, or passed to a `$`-parameter. It cannot be returned, stored in a field or list, bound to a plain name, or compared with `==`. The result of a `try` must be first-class, since the capabilities it introduces end with it.
4. A first-class value may be passed to a `$`-parameter, or bound to a `$`-local, because both only promise that the value will not escape. Binding a first-class value to a `$`-local **demotes** it: from then on it is second-class.

```duetto
$nf = $errs.not_found,               # allowed: second-class local
nf = $errs.not_found,                # error: second-class value bound to a plain name
r = { on_missing: $errs.not_found }, # error: a second-class record bound to a plain name
$r = { on_missing: $errs.not_found }, # allowed: a second-class record in a $-local
```

**Fields of second-class records.** A projection from a second-class record is second-class even when the field holds an ordinary value: `$h.config` is second-class whether or not `config` is a function. Types do not record which fields of a record are second-class (section D9.5), so the class of a path cannot depend on the field. A first-class value needed after the call should be passed as a separate argument. This keeps one rule for all paths, at the cost of the per-field precision discussed in section 4.8.

#### D9.2 `$`-parameters in higher-order code

By rule 4, `map = (xs, $f) -> ...` accepts both ordinary functions and closures that capture raisers. Library authors should mark a function parameter with `$` whenever the function only calls it and never stores or returns it, which is the common case. In a signature, `$f` documents "this is only called."

Spec extraction follows the same model: a spec that passes a second-class value to `map`, such as a capturing callback or a demoted function, establishes that `map`'s parameter is a `$`-parameter (section D12.4).

#### D9.3 Interaction with recipes

Recipes are values catalogued from specs. Because second-class values cannot be stored or returned, no recipe can contain a capability. This rules out a value captured inside one spec's `try` being reused, with a dead raiser, by an unrelated spec.

#### D9.4 Payloads

Payloads passed to raisers are first-class values, so they cannot contain `$` values. A capability can never escape its `try` through an error payload.

#### D9.5 Second-class records and `$` in function types

**Second-class records.** A record literal with any second-class field is itself second-class. Like any second-class value, it may only be called into, projected, bound to a `$`-local, or passed to a `$`-parameter; it cannot be returned or stored. Every projection from it is second-class (section D9.1).

```duetto
result = e.match({
  num: n -> check(n, $errs.too_big),   # second-class branch
  add: (l, r) -> ...,
}),                                     # allowed if match takes a $-parameter
```

**`$` in function types.** A function type may mark a parameter as second-class, so type aliases can express it:

```text
match: ($ { num: (Num) -> ?R, add: (Expr, Expr) -> R }) -> R
```

Without this, `$` would exist only on parameter names, and no alias could describe a function that accepts second-class arguments. Both handler encodings in section D13.4 depend on it.

### D11. Doubles with raisers

From former section 11, the stub rules that concerned second-class values:

- The spec **stubs** responses for specific inputs. Entries are comma-separated, of two forms: `fn(args) returns expr`, and `fn(args) raises $r(payload)`.
- In a stub's arguments, a first-class argument is a value, matched against the actual argument with `==`. A second-class argument is written as a `$`-name, such as `$nf`: it matches any value without comparing it, since `==` rejects second-class values, and binds it for the response. A parameter written as a `$`-name in any stub is a `$`-parameter of the double's function.
- The response is evaluated **at call time**, in the caller's context, and may use the `$`-names its stub bound, but no other `$`-name: a response that mentions an outer `$`-name is a compile error, so a double never holds a capability and stays first-class.
- `raises $r(payload)` calls the raiser `$r`, which must be a `$`-name bound by the same stub, and so unwinds to the caller's `try`. This is how a double exercises a failure path (section D11.1). The form is separate from `returns` because it fixes `$r`'s type as a raiser, `(P) -> Never` with `P` the payload's exact type (section D12.6). A `returns` response may also call a bound `$`-name, for example a callback passed to a higher-order function, but that call is typed as an ordinary call.
- **Shape of a recorded call.** `calls` records only first-class arguments: a second-class argument, such as a raiser, is dead once the call returns.

#### D11.1 Testing failure paths

A dependency can only fail if it is given a raiser (section D8), so a capability that may fail takes one per call, like any other function: `read_text: (String, $ ({ path: String }) -> Never) -> String`. A double for it binds the raiser in its stubs, and raises through it in the failing case:

```duetto
read_file: (fs, path, $nf) -> fs.read_text(path, $nf),

spec read_file returns content or reports a missing file {
  fs = double {
    read_text("ok.cfg", $nf) returns "content",
    read_text("a.cfg", $nf) raises $nf({ path: "a.cfg" }),
  },
  ok = try $errs {
    <<read_file(fs, "ok.cfg", $errs.not_found)
  } case not_found(e) -> "missing: " ++ e.path,
  missing = try $errs {
    <<read_file(fs, "a.cfg", $errs.not_found)
  } case not_found(e) -> "missing: " ++ e.path,
  ensure ok == "content",
  ensure missing == "missing: a.cfg",
},
```

Extracted: `read_file : ({ read_text: (String, $ ({ path: String }) -> Never) -> String }, String, $ ({ path: String }) -> Never) -> String`.

- The spec supplies the real raiser, through its own `try`. `try` is pure, so it may be used in specs.
- The double **holds no raiser**. It receives one for the duration of each call, so it stays first-class.
- **One spec must cover both paths.** A signature comes from one fully constrained use, never from a combination of several specs (formal core, section 6.4). A spec with only the raising stub would not fix what `read_text` returns, and one with only the success stub would not fix the raiser's type. One double with both stubs fixes the whole type of `read_text`, since the stubs of one function share its parameter and result types (section D12.6).
- The raiser's `-> Never` comes from two places: the double's `raises` stub fixes it for `read_text`'s parameter, and the `try` fixes it for `read_file`'s third parameter, since every raiser a `try` introduces returns `Never` (section D8.2).
- The payload `{ path: String }` is exact on both sides. The stub's payload is a record literal, and the handlers' payload consists of the fields they use (section D12.6). The two must agree, or checking `read_file`'s body, which passes the one raiser where the other is expected, fails.
- The spec establishes that `read_file`'s third parameter is a `$`-parameter (section D12.4).

### D12.4 Second-class parameters

A parameter is a `$`-parameter in the signature exactly when some spec passes it a second-class value. As with types, the signature comes from specs, not from the implementation.

- **Establishing a `$`-parameter needs no raiser.** A spec can demote any value by binding it to a `$`-local (section D9.1), and pass that:

  ```duetto
  spec map can take a second-class function {
    $times_two = x -> x * 2,
    ensure map([1, 2], $times_two) == [2, 4],
  },
  ```

- **A definition's `$` must agree with the signature.** A field definition may write `map: (xs, $f) -> ...` to document its intent, and its body is then checked against the `$`. If no spec establishes the `$`, the definition and the signature disagree, which is an error: "`map` declares `$f`, but no spec passes it a second-class value." Without this rule, callers could not pass second-class values to a parameter the implementation was written to accept them.
- When a spec establishes a `$`-parameter that the definition does not mark, the body is still checked against the signature, so it must not let that value escape.

### D12.6 Raisers and doubles in extraction

Raisers and doubles take part in extraction like any other values, with these rules. They are outside the formal core's current fragment, and the `$` and `try` step must formalize them (formal core, section 9.3).

1. **A raiser's result is `Never` by construction.** Every raiser a `try` introduces has type `(P) -> Never` (section D8.2). This is not the defaulting of the formal core's section 5.3, which applies only to empty lists: it is the raiser's declared type.
2. **A raiser's payload is exact, and consists of the fields its handler uses.** `P` is the handler parameter's type, always a record, since a raiser takes a single payload record. If its row is still open after solving, as when a handler only projects `e.path`, it is closed to the fields used: `{ path: String }`. This is the general rule that open rows in positive positions are closed to the observed fields (formal core, section 5.3): a payload is passed to a raiser that is itself a parameter, so it is in a positive position. It matches section D8.2, where every payload is exactly typed, and it is the record counterpart of the label rule of section 12.3. In production code the payload is usually fixed by the signatures of the functions the raiser is passed to, so the row is rarely open. A handler that ignores its payload gives the payload `{}`.
3. **A double's type is the type its stubs give it.** The stubs of one function share its parameter and result types. A `returns e` stub unifies the result with `e`'s type. A `raises $r(p)` stub types `$r` as `(τp) -> Never`, where `τp` is the exact type of the payload `p`, and places no constraint on the result. A parameter written as a `$`-name is a `$`-parameter.
4. **Raisers and doubles follow the one-use rule.** A field's signature comes from one fully constrained use (section 12.2), so a spec that exercises a fallible capability should cover both its success and its failure in one double, as in section D11.1.

Rule 2 makes a spec too narrow: a handler that uses only `path` gives the payload `{ path: String }`, so an implementation that raises `{ path, line }` fails its check, and a handler that ignores its payload gives `{}`, which no implementation that raises a real payload can satisfy. The payload type then comes from the wrong side: from what the spec's handler happens to read, not from what the implementation raises.

**Proposal: polymorphic payloads.** A handler that reads only `path` accepts any payload with a `path`, so its raiser's honest type is `∀R. ({ path: String, ..R }) -> Never`. The proposal replaces rule 2 with these rules; it is scheduled with the `$` and `try` formal step (section 13.3), not with general rank-2 polymorphism (section 13.4).

- **A handler is generalized like a lambda local.** After typing a handler branch, the free type and row variables of its payload that are not free in the environment are quantified, and the raiser it defines gets the quantified type. A handler that reads only `e.path` gives `∀R. ({ path: String, ..R }) -> Never`; one that ignores its payload gives `∀R. ({ ..R }) -> Never`.
- **Only raisers may be polymorphic in this way.** A `$`-parameter's type may be a quantified raiser type, `∀… . (P) -> Never`, with the quantifier directly on the raiser. This is a narrow case of rank-2 polymorphism: raisers are second-class, so a polymorphic raiser is never stored, returned, or placed inside data. It only flows down into callees.
- **Calling a polymorphic raiser instantiates it.** `$nf({ path: p, line: 3 })` instantiates `R := { line: Num }`. Passing it where a monomorphic raiser is expected, such as a double's `({ path: String, line: Num }) -> Never`, instantiates it the same way.
- **Passing a raiser to a polymorphic `$`-parameter requires it to be at least as polymorphic.** A caller whose handler compares the payload with an exact record cannot pass its raiser to `read_file`, which may raise any extension of `{ path }`. This is correct, not a limitation: the handler would mishandle the extra fields.
- **Extraction counts a quantified raiser type as fully constrained.** In section D11.1, `read_file` would get `$ ({ path: String, ..?R }) -> Never` for its third parameter, where `?R` is quantified over that parameter only.
- **It is sound with `==`.** A handler that compares its payload with an exact record, `e == { path: "a" }`, fixes the payload's row while it is typed, so it is not generalized: its raiser is monomorphic, and cannot be passed where any extension may be raised (the previous rule). No comparison ever silently ignores hidden fields. Simply allowing extra fields in payloads would not have this property: the same comparison would quietly compare only `path`.

General rank-2 polymorphism, when it arrives, subsumes this case.

### D13.4 Handler-interface `case` sugar

A value can carry its own dispatch: a `match` field taking a record of branches.

```duetto
Expr: { match: ($ { num: (Num) -> ?R, add: (Expr, Expr) -> R }) -> R },

num = n -> { match: $h -> $h.num(n) },
add = (l, r) -> { match: $h -> $h.add(l, r) },

eval = e -> case e {
  num(n) -> n,
  add(l, r) -> eval(l) + eval(r),
},
```

This **record encoding** desugars a handler `case` to calling the value's `match` field: `e.match({ num: n -> n, add: (l, r) -> ... })`. Exhaustiveness comes from exact records, and equality from function equality: `num(1) == num(1)` is `'true`. It suits values defined by behavior, such as streams or visitors.

It requires **rank-2 polymorphism**, since `?R` in `match` must be quantified per call. It also requires **second-class records and `$` in function types** (section D9.5): if a branch calls a raiser, the branch closure is second-class, so the branch record is second-class and `match` must take it as a `$`-parameter. Rank-2 polymorphism alone does not address escape.

**Dispatch is syntactic.** The kind of `case` is determined by its branch form, never by the scrutinee's type: `'lt ->` is a label `case`, `{ num } ->` is an untagged-union `case`, and `num(p) ->` is handler dispatch, through `match` or through a `try` (below). The meaning of a `case` never depends on types extracted from specs.

#### The `try` encoding (deferred)

A value can instead be a **dispatcher** that receives a `$` record of raisers and calls exactly one:

```duetto
num = n -> $h -> $h.num({ n }),
add = (l, r) -> $h -> $h.add({ l, r }),

eval = e -> try $h { <<e($h) } case {
  num(p) -> p.n,
  add(p) -> eval(p.l) + eval(p.r),
},
```

- **No rank-2 polymorphism.** The dispatcher returns `Never`, and the result arrives through the `try`, so there is no `?R` to quantify. A value's type is `($ { num: ({ n: Num }) -> Never, add: ({ l: Expr, r: Expr }) -> Never }) -> Never`.
- **Branches may use `$` values.** Handler branches are the `try`'s own continuation code, not closures stored in a record, so they can freely use enclosing `$` values.
- It requires **`$` in function types** (section D9.5).
- Raisers take a single payload record, so branches are written `add(p)`. Writing `add(l, r)` would need sugar for destructuring the payload.
- Each match unwinds once, which is a performance question for later, not a semantic one.
