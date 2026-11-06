# Duetto: Formal Core

Nov 6, 2026 · @Alb

## 1. Purpose and scope

This document specifies the formal core of Duetto: the typing rules, spec elaboration, and extraction of public signatures from specs. It covers steps 1 and 2 of the design draft's section 13.3, typing and generalization and row unification, which every later feature depends on.

The core is a deliberately small fragment:

- **Included:** `Int` and `String`; labels and label `case`; exact records and open rows; lists; lambdas and application; `==`; structs with fields, locals, and recursive groups; and spec entries with `some`, `?` variables, and `ensure`.
- **Excluded for now:** `try` and raisers, `$` values, recipes and function-carrying `some`, doubles, `every`, untagged record unions, the initialization-order check, and `do`.

Excluded features are added in later steps, each as an extension of these rules. The design draft remains the source of intent; where this document is more precise, it is authoritative for the fragment it covers.

**Notation.** Rules are written as `premises ⟹ conclusion`. Metavariables:

| Symbol | Ranges over |
| --- | --- |
| `τ`, `σ` | types and schemes |
| `α`, `β` | flexible type variables, solved by unification |
| `ℓ` | flexible label-set variables, with bounds |
| `ρ` | flexible row variables |
| `â`, `ρ̂` | rigid type and row variables (skolems), from `?` and `..` in specs |
| `X`, `R` | type and row generalization variables, quantified in schemes |
| `Λ` | lacks sets: field names a row must not contain |
| `L` | concrete finite sets of labels |
| `e` | expressions |
| `Γ` | typing environments |

## 2. Abstract syntax

### 2.1 Types

```text
τ ::= Int | String
    | L                            -- concrete label set, e.g. {'lt, 'eq, 'gt}
    | ℓ                            -- label-set variable, with bounds (section 3.2)
    | [τ]                          -- list
    | { f1: τ1, ..., fn: τn | r }  -- record with row tail r
    | (τ1, ..., τn) -> τ           -- function
    | α | â | X                    -- flexible, rigid, generalization type variables

r ::= ∅                            -- closed: an exact record
    | ρ | ρ̂ | R                    -- flexible, rigid, generalization row variables

σ ::= ∀X1...Xn, (R1 lacks Λ1)...(Rm lacks Λm). τ   -- signature scheme
```

A label-set variable `ℓ` is distinct from an ordinary flexible variable `α`: `ℓ` can only stand for a set of labels, while `α` can stand for any type, including a label set.

- A singleton label type `'a` is the set `{'a}`. The alias `Bool` is `{'true, 'false}`.
- Surface `{ f: T }` is `{ f: T | ∅ }`, surface `{ f: T, .. }` is `{ f: T | ρ }` with a fresh `ρ`, and surface `{ f: T, ..?R }` is `{ f: T | ρ̂ }`.
- Field order is irrelevant; records are equal up to permutation of fields.
- Type aliases are expanded before typing. Recursive aliases are excluded from the core.
- A zero-argument function `() -> τ` is `({ | ∅ }) -> τ`, a function from the empty record.

### 2.2 Expressions

```text
e ::= n | s | 'a                -- Int, String, label literals
    | x                         -- variable
    | [e1, ..., en]             -- list
    | { f1: e1, ..., fn: en }   -- record literal (exact)
    | e.f                       -- projection
    | (x1, ..., xn) -> e        -- lambda
    | e(e1, ..., en)            -- application
    | e1 == e2                  -- equality
    | case e { 'a1 -> e1, ..., 'an -> en }  -- label case
    | S                         -- struct (block or record)
```

Built-in operators such as `+` and `length` are constants with fixed types in the initial environment `Γ₀`, for example `+ : (Int, Int) -> Int` and `length : ∀X. ([X]) -> Int`.

### 2.3 Structs and specs

```text
S     ::= { E1, ..., En }
E     ::= f: e                  -- field
        | x = e                 -- local
        | << e                  -- block result (last entry only)
        | spec t { P1, ..., Pn }

P     ::= x = e | x = some(T) | ensure e
T     ::= surface type, possibly with ?A and ..?R
```

A file is the body of a struct. A struct with `<<` is a **block**; a struct without one is a **record** whose fields are its `f: e` entries. Spec titles are not significant in the core.

A binding whose right-hand side is syntactically a lambda is a **lambda binding**; any other binding is **computed**. Within a struct, lambda bindings form one recursive group (section 4).

## 3. Typing expressions

Typing is constraint-based. The judgment `Γ ⊢ e : τ ⊣ C` says that `e` has type `τ` under the constraints `C`. Constraints are of two kinds:

- **Equations** `τ1 ~ τ2`, solved by unification (section 3.3).
- **Label inclusions** `L ⊆ ℓ` and `ℓ ⊆ L`, where `ℓ` is a label-set variable (section 3.2).

Unification and inclusion solving are standard, so the rules below list only what each form contributes.

### 3.1 Rules

```text
[Var]     Γ(x) = ∀X1...Xn, (R1 lacks Λ1)...(Rm lacks Λm). τ
          ⟹  Γ ⊢ x : τ[Xi := αi, Rj := ρj]      (αi, ρj fresh;  Λ(ρj) = Λj)

[Int]     Γ ⊢ n : Int          [Str]  Γ ⊢ s : String

[Label]   ⟹  Γ ⊢ 'a : ℓ ⊣ {'a} ⊆ ℓ                        (ℓ fresh)

[List]    Γ ⊢ ei : τi   (each i)
          ⟹  Γ ⊢ [e1, ..., en] : [α] ⊣ τi ~ α             (α fresh)

[Rec]     Γ ⊢ ei : τi   (each i, fields distinct)
          ⟹  Γ ⊢ { f1: e1, ..., fn: en } : { f1: τ1, ..., fn: τn | ∅ }

[Proj]    Γ ⊢ e : τ
          ⟹  Γ ⊢ e.f : α ⊣ τ ~ { f: α | ρ }      (α, ρ fresh;  Λ(ρ) = {f})

[Lam]     Γ, x1: β1, ..., xn: βn ⊢ e : τ
          ⟹  Γ ⊢ (x1, ..., xn) -> e : (β1, ..., βn) -> τ   (βi fresh)

[App]     Γ ⊢ e : τ    Γ ⊢ ei : τi
          ⟹  Γ ⊢ e(e1, ..., en) : α ⊣ τ ~ (τ1, ..., τn) -> α

[Eq]      Γ ⊢ e1 : τ1    Γ ⊢ e2 : τ2
          ⟹  Γ ⊢ e1 == e2 : ℓ ⊣ τ1 ~ τ2, {'true, 'false} ⊆ ℓ

[Case]    Γ ⊢ e : τ    Γ ⊢ ei : τi    B = {'a1, ..., 'an}
          ⟹  Γ ⊢ case e { 'a1 -> e1, ... } : α
              ⊣ τ ~ ℓ, ℓ ⊆ B, τi ~ α                       (ℓ, α fresh)
```

Lambda parameters are monomorphic. A record literal is always exact; only rows introduced by `..` in specs, or by projection, are open.

**Branches of `case`.** In `[Case]`:

- **Duplicate labels are an error.** The branch labels `'a1, ..., 'an` must be distinct.
- **Extra branches depend on the scrutinee's type.** If the scrutinee's type is a concrete set `L`, from a signature, an alias, or `some(T)`, every branch label must be in `L`; a branch outside it is unreachable, and an error. If the scrutinee's type is a label-set variable `ℓ`, extra branches are allowed: the branches define the upper bound `L⁺(ℓ)`, the labels the code is prepared to handle.

In specs, branches on a field's result are of the second kind, so their labels contribute to the field's signature (section 6.3).

### 3.2 Label sets

A label-set variable `ℓ` stands for an unknown finite set of labels. It carries two bounds:

- a **lower bound** `L⁻(ℓ)`: labels that may flow into it, initially `∅`;
- an **upper bound** `L⁺(ℓ)`: labels that are handled, initially "any label" (written `⊤`).

The constraints `{'a} ⊆ ℓ` (from a literal) and `ℓ ⊆ B` (from a `case`) adjust these bounds: `L⁻(ℓ) := L⁻(ℓ) ∪ {'a}` and `L⁺(ℓ) := L⁺(ℓ) ∩ B`. After every adjustment, the solver checks the **bound invariant** `L⁻(ℓ) ⊆ L⁺(ℓ)`. A violation means some label can reach a `case` that does not handle it, which is a type error.

**Unification with label sets.** The equation `τ1 ~ τ2` is extended as follows:

```text
ℓ ~ ℓ'     merge: one variable, with L⁻ := L⁻(ℓ) ∪ L⁻(ℓ'),  L⁺ := L⁺(ℓ) ∩ L⁺(ℓ');
           check the bound invariant

ℓ ~ L      bind ℓ := L;  check L⁻(ℓ) ⊆ L ⊆ L⁺(ℓ)

L ~ L'     require L = L'

α ~ ℓ      bind α := ℓ         (α may stand for any type)

ℓ ~ τ      error, if τ is not a label set or a variable
```

A concrete set `L` comes from a signature, a type alias such as `Bool`, or `some(T)`. It behaves as a rigid set: it never grows or shrinks, and every constraint against it becomes a check. This gives the behavior the examples rely on:

- **Passing a label** `'a` to a parameter of signature type `{'a, 'b}` binds the literal's `ℓ` to `{'a, 'b}` and checks `{'a} ⊆ {'a, 'b}`.
- **A `case` on a parameter** of type `L` with branches `B` checks `L ⊆ B`: exhaustiveness.
- **Returning** `'gt` where the signature's result is `{'lt, 'eq}` checks `{'gt} ⊆ {'lt, 'eq}` and fails (case R6).

**Solutions.** At the end of solving, an unbound `ℓ` denotes its lower bound `L⁻(ℓ)`. In a spec, the pair `(L⁻(ℓ), L⁺(ℓ))` is what section 5.3 records as a label position, with `L⁺` absent when it is still `⊤`. These pairs are what extraction joins (section 6.3), which is how cases A6 and R7 are decided.

**No generalization.** Label-set variables are never generalized, in locals or elsewhere. All uses of a local share its label-set variables, which is conservative but avoids bounded quantification. Signatures contain only concrete sets.

Label sets in invariant positions, such as inside lists or record fields, are unified like any other type, so they are merged rather than compared by inclusion. This keeps the solver to unification plus bound checks.

### 3.3 Row unification

Records unify field by field, with row tails absorbing missing fields. Write `F` for a set of fields.

```text
{ F | ∅ } ~ { F' | ∅ }    fields(F) = fields(F'); unify common fields

{ F | ρ } ~ { F' | r' }   unify common fields, then:
  if fields(F) ⊆ fields(F')     ρ := { F'∖F | r' }
  else if r' = ρ2 (flexible)    ρ := { F'∖F | ρ1 },  ρ2 := { F∖F' | ρ1 }   (ρ1 fresh)
  else                          error: F∖F' cannot be absorbed

{ F | ρ̂ } ~ { F' | ρ̂ }    fields(F) = fields(F'); unify common fields
```

The second rule also applies symmetrically, with the sides swapped. Any other combination is an error.

- A rigid row `ρ̂` unifies only with itself. It can never absorb or supply fields, which is what makes `{ name: String, ..?R }` mean "some fixed but unknown other fields."
- A closed row `∅` unifies only with `∅`, or with a flexible row that becomes `∅`. This is exactness: there is no width subtyping.
- Unification includes an occurs check for both type and row variables.

**The lacks invariant.** Field names in a record type are always distinct, including fields that a row variable may later expand into. Every row variable carries a **lacks set** `Λ(ρ)`, the field names it must not contain, and unification maintains it:

- A row tail introduced next to fields `F` lacks them: in `{ F | ρ }`, `fields(F) ⊆ Λ(ρ)`. This holds for fresh rows from `[Proj]`, for rigid rows from `..` and `..?R` in specs, and for generalization variables in schemes.
- **Binding to an extension**, `ρ := { F | r1 }`, checks the fields against **both** rows and then **combines** their lacks sets, never overwriting either:
  - `fields(F) ∩ Λ(ρ) = ∅`, since `ρ` may not contain those fields;
  - if `r1` is a flexible `ρ1`, also `fields(F) ∩ Λ(ρ1) = ∅`, and then `Λ(ρ1) := Λ(ρ1) ∪ Λ(ρ) ∪ fields(F)`;
  - if `r1` is rigid, `ρ̂` or a rigid instance of `R`, its lacks set cannot grow, so `Λ(ρ) ∪ fields(F) ⊆ Λ(ρ̂)` is required instead;
  - if `r1` is `∅`, nothing more is needed.
- **Merging rows**, `ρ := r'`: if `r'` is a flexible `ρ'`, then `Λ(ρ') := Λ(ρ') ∪ Λ(ρ)`; if `r'` is rigid, `Λ(ρ) ⊆ Λ(r')` is required.
- Instantiating `R` in a scheme copies its lacks set to the fresh row.

Any failed check is an error: some field would appear twice.

Without this invariant, duplicates arise. If `v : { a: Int | ρ }` is passed to a function of type `({ a: Int | R }) -> { | R }`, the result has type `{ | ρ }`; projecting `.a` from it would set `ρ := { a: β | ρ2 }`, making `v`'s type `{ a: Int, a: β | ρ2 }`. With the invariant, `a ∈ Λ(ρ)`, and the projection is rejected.

## 4. Structs, recursive groups, and locals

### 4.1 Two kinds of names

Inside a struct, names are typed differently depending on what they are:

- **Fields** have **given** signatures. Their schemes `σf` come from extraction (section 6), so every use of a field, in production code or another field, instantiates `σf`. A field's own definition is then **checked** against `σf` (section 7).
- **Locals** have **inferred** types, by Hindley–Milner inference over their definitions.

Because field signatures are given, fields may be used at different instances of their scheme anywhere in the struct, including recursively. Only locals need inference order.

### 4.2 Typing locals

Locals are typed in dependency order, not textual order:

1. Build the dependency graph of the struct's locals: `x` depends on `y` if `y` occurs in `x`'s right-hand side.
2. Compute its strongly connected components, and type them in topological order.
3. Within a component, each local `x` gets a fresh `αx`; the right-hand sides are typed with those assumptions, and `Γ ⊢ ex : τx` adds `αx ~ τx`.
4. After solving the component, **lambda bindings are generalized** over the variables that are not free in `Γ`. Computed bindings stay monomorphic.

A component with more than one local can only consist of lambda bindings, since computed bindings never refer to themselves through other bindings; that restriction belongs to the initialization-order check (design draft, section 3.5), which is outside the core. The core assumes it holds.

The visibility rule, that computed bindings are visible only to later entries, is a separate syntactic check on scope; it does not affect typing.

### 4.3 The type of a struct

```text
[Block]    entries typed as above;  last entry  << e,  Γ' ⊢ e : τ
           ⟹  Γ ⊢ { E1, ..., << e } : τ

[Record]   entries typed as above;  fields f1, ..., fn with types τ1, ..., τn
           ⟹  Γ ⊢ { E1, ..., En } : { f1: τ1, ..., fn: τn | ∅ }
```

Locals and spec entries do not appear in the struct's type. A block may not contain fields. A file is the body of a record struct.

Nested structs follow the same rules, so a local helper inside a block is inferred, while a field of a nested record literal is just a field of that record's type. Only the fields of the **file** are public, so only they receive signatures from specs. Fields of nested records are typed like any other expression (section 7.3).

## 5. Spec elaboration and usage types

A spec is typed before any field has a signature. Its job is to produce **usage types**: one per occurrence of a field in the spec body.

### 5.1 The spec environment

A spec body is typed in `Γspec`, which contains `Γ₀`, the type aliases in scope, and the spec's own bindings. Fields are not in `Γspec` with a type. Instead:

```text
[FieldUse]   f is a field of the file
             ⟹  Γspec ⊢ f : αk,   recording the usage  (f, αk)      (αk fresh)
```

Each occurrence `k` gets its own variable, so two calls to `f` in one spec are two usages. A field used as a value, for example passed to `map`, is a usage like a call.

In the core, **specs may not mention locals** (section 9).

### 5.2 Spec statements

```text
[Some]     T elaborated with:  ?A ↦ â (fresh rigid),  ..?R ↦ ρ̂,  .. ↦ fresh rigid row
           ⟹  binding x = some(T)  gives  x : T̂

[Let]      Γspec ⊢ e : τ   ⟹   binding x = e  gives  x : τ   (monomorphic)

[Ensure]   Γspec ⊢ e : τ
           ⟹  ensure e  adds  τ ~ ℓ,  ℓ ⊆ {'true, 'false}
```

A `?A` is rigid in the spec that introduces it: the spec states a fact for every `A`. Later occurrences of `A` in the same spec refer to the same `â`. An anonymous `..` inside `some` is also rigid, since `some({ name: String, .. })` means "any record that has `name`."

### 5.3 Solving and usage types

After typing the body, the spec's constraints are solved. Then:

1. **Rigid variables must stay rigid.** If solving would bind `â` or `ρ̂` to anything other than itself, the spec is ill-typed. For example, `x = some(?A), ensure x == 1` treats `A` as `Int`, and is reported as such.
2. **Each usage `(f, αk)` yields the usage type** `Uk = solve(αk)`. Rigid variables remain in `Uk`. Flexible variables left unconstrained also remain; section 6.4 says when that is allowed.
3. **Label-set variables keep their bounds.** A label position in `Uk` is a pair `(L⁻, L⁺)`: the labels that flow into that position, and the labels the spec handles there (with `L⁺` absent if the spec places no upper bound). A label position with neither bound counts as unconstrained.

The outputs of a spec, as far as the core is concerned, are its usage types. Runtime execution of specs is unchanged from the design draft.

## 6. Extraction by anti-unification

For each field `f`, extraction takes all usage types `U1, ..., Un` of `f`, from every spec, and produces either a signature `σf` or a conflict. Rigid variables from different specs are distinct; rigid variables are treated as constants until the last step.

### 6.1 Anti-unification

Anti-unification walks the usage types in parallel, position by position. At each position it sees a tuple `t = (s1, ..., sn)` of subterms, one per usage.

```text
lgg(t):
  drop flexible variables from t                       -- they agree with anything
  if t is empty                → unconstrained position (section 6.4)
  if all si have the same head → that head, with lgg applied to each component:
       Int, String             (no components)
       [ · ]                   the element types
       (·, ..., ·) -> ·        same arity: parameters and result
       { F | r }               see 6.2
       â                       the same rigid variable in every si
       label position          see 6.3
  otherwise                    → the generalization variable X_t
```

**The same tuple always yields the same variable.** If two positions see the same tuple `t`, they get the same `X_t`. This is what preserves relationships between positions: usages `(â) -> â` and `(Int) -> Int` see `(â, Int)` at both the parameter and the result, so both become one `X`, giving `(X) -> X`, never `(X) -> Y`.

**Last step.** Each rigid variable that survives in the result, because every usage agreed on it, also becomes a generalization variable. A single usage `(â) -> â` therefore gives `(X) -> X`.

### 6.2 Records and rows

For a tuple of record types `{ Fi | ri }`:

- Let `C` be the fields present in **every** usage. Each field in `C` is anti-unified componentwise.
- The **remainders**, each usage's other fields plus its tail, form a row tuple `(R1, ..., Rn)`.
- If every remainder is the same closed `∅`, the result is exact: `{ C | ∅ }`. If every remainder is the same rigid row `ρ̂`, the result keeps it.
- Otherwise the remainders become a **row generalization variable**, `{ C | R_t }`, and the signature is chosen by the rule of 6.4.

So `{ num: Int | ρ̂ }` and `{ num: Int, b: Int | ∅ }` give `{ num: Int | R }`, and the open usage is the most general one (6.4): the exact usage is its instance with `R := { b: Int | ∅ }`. But `{ name: String | ∅ }` and `{ name: String, age: Int | ∅ }` have no most general usage, since neither is an instance of the other, so they conflict. This is exactness: different record shapes are never joined implicitly.

### 6.3 Label positions

Label positions are joined, not generalized. This is the deliberate exception of section 12.3 of the design draft. For a tuple of label positions `(L⁻i, L⁺i)`:

- The signature's set is `S = ⋃ L⁻i ∪ ⋃ L⁺i`: every label that flows in, and every label some spec is prepared to handle.
- **Check:** for each usage with an upper bound, `S ⊆ L⁺i`. Otherwise that spec handles too few labels: "spec Q's `case` does not handle `'foo`, which reaches this position in spec P."
- A rigid label set, such as one from `some(Bool)`, contributes its labels as both bounds.

**Typos in handled labels.** Because handled labels contribute to `S`, a misspelled branch in a spec's `case`, such as `'bogus` for `'gt`, enters the signature. This is accepted deliberately: every other `case` on the same result, in other specs through the check `S ⊆ L⁺` and in production code through exhaustiveness, then fails to cover `'bogus`, so the typo is reported at nearly every point of use except the one where it was made.

### 6.4 Choosing the signature

The signature must be exactly what one spec wrote:

> **One usage must be the most general.** Let `gen(U)` be the usage `U` with its rigid type and row variables replaced by generalization variables, keeping their lacks sets. For a candidate usage `U*`, the **candidate signature** is
>
> `σ(U*) = gen(U*)`, with **every label position replaced by its joined set `S`** from section 6.3, computed over all usages at that position.
>
> The signature is `σf = σ(U*)` for some usage `U*` such that
>
> 1. `U*` is **fully constrained**: it contains no flexible type or row variables, and every label position has a non-empty joined set `S`; and
> 2. **every** usage `U` is **compatible** with it: `U ⊑ σ(U*)`.
>
> If no usage qualifies, extraction fails.

So the chosen usage supplies the type and row **structure** and the **relationships** between positions, while label sets come from **all** usages. Labels are the deliberate exception to "exactly what one spec wrote." In case A6, either usage supplies the structure `(L) -> Int`, and the join gives `L = {'true, 'false}`. A label position is unconstrained only if no usage bounds it at all, in which case `S = ∅` and the usage is not fully constrained.

**Compatibility.** `U ⊑ σ` holds if, after replacing each label position `(L⁻, L⁺)` in `U` with the signature's label set `S` at the same position (section 6.3), `U` is an instance of `σ`, and at every label position `L⁻ ⊆ S ⊆ L⁺` (the upper bound is omitted when absent). In the instance check, `U`'s own rigid variables are constants, and its flexible variables match anything. No separate rule is needed for parameter and result positions: a spec that supplies a label contributes only to `L⁻`, and a spec that handles labels contributes `L⁺`, so the bracket covers both, including callbacks, where polarity flips.

**Unconstrained positions.** Flexible variables are allowed in usages other than `U*`, where they act as wildcards. This is what allows `ensure length(reverse(xs)) == length(xs)`, which never constrains the element type of `reverse`'s result, as long as another spec pins it down. If the only candidate for `U*` leaves a position unconstrained, extraction fails with a precise diagnostic: "the most general use of `f` (spec P) does not constrain its result; add an `ensure` that does." Because the signature always comes from one fully constrained usage, holes are never filled by guessing.

Anti-unification (6.1) is used for **diagnostics**: when usages conflict, the positions where their tuples disagree show where the specs differ. The report names those specs, and suggests `some(?A)` where a concrete usage was probably meant to be generic.

Signatures are printed with `?` on the first occurrence of each variable, as in `identity : (?X) -> X`.

### 6.5 Properties

- **Every usage is compatible with `σf`** (`U ⊑ σf`), by definition. Compatibility is instantiation up to label positions, where each usage's label bounds bracket the signature's set.
- **Generality is never invented.** The signature's type and row structure is always exactly what one spec wrote, never a combination of what several specs wrote. Only label sets are joined across specs.
- **Holes are never guessed.** The usage that becomes the signature is fully constrained.
- **Relationships are preserved.** A relationship stated by a generic spec, such as "both parameters have the same type" in `(â, â) -> â`, can be relaxed only by another spec that explicitly states the more general contract, as in `(b̂, ĉ) -> b̂`. A concrete usage like `(Int, String) -> Int` cannot relax it.
- **Partially generic specs do not combine.** Usages `(â, Int) -> â` and `(Int, b̂) -> Int` are each generic in a different parameter; neither is compatible with the other, so they conflict. To get `(?X, ?Y) -> X`, a spec must be generic in both.

## 7. Production checking

### 7.1 The checking environment

Once every field has a signature, production code is typed in

```text
Γsig = Γ₀, type aliases, f1 : σf1, ..., fk : σfk
```

Locals are inferred in `Γsig` as in section 4.2, so a local may use any field at any instance of its signature.

### 7.2 Checking a field

A field `f: e` is checked, not inferred:

```text
[Check]   σf = ∀X1...Xm, (R1 lacks Λ1)...(Rk lacks Λk). τf
          Γsig ⊢ e : τ ⊣ C
          C, τ ~ τf[Xi := x̂i, Rj := r̂j]  solvable      (x̂i, r̂j fresh rigid;  Λ(r̂j) = Λj)
          ⟹  f: e  is well-typed
```

The generalization variables become rigid, so the implementation must work uniformly for every instance: it cannot use an `X` as an `Int`. Label sets in `σf` are rigid too, and the inclusion constraints of section 3.2 turn into checks:

- **In parameter positions**, every label in the signature's set must be handled. A `case` with branches `B` on a parameter whose set is `S` requires `S ⊆ B`.
- **In result positions**, the implementation may produce only labels in the signature's set. Producing `'gt` where the signature says `{'lt, 'eq}` is an error: "`f` returns `'gt`, which no spec observes or handles."

The second rule follows directly from section 6.3, and matches the design draft's intent that every label of a public interface is exercised by some spec.

This is how the design draft's rule that "an implementation cannot strengthen its required input shape or change its return type" is enforced: the implementation's type must match the signature exactly, up to the rigid variables.

### 7.3 Nested records

Fields of nested record literals, including fields of record values returned by functions, are typed by `[Rec]` like any other expression. Only the file's own fields are public and receive signatures.

### 7.4 Pipeline

1. **Elaborate every spec** (section 5), producing usage types. Ill-typed specs, including rigid-variable violations, are reported here.
2. **Extract a signature for every field** (section 6). Conflicts are reported here.
3. **Every field must have at least one usage.** A field no spec mentions has no signature: "no spec uses `f`."
4. **Infer locals and check fields** in `Γsig` (sections 4.2 and 7.2). Diagnostics for a field that fails its check name the specs whose usages produced the conflicting part of its signature.
5. **Run specs**, as in the design draft. This step is outside the core.

## 8. Test cases

These cases pin down the rules. Each lists the usage types that elaboration produces and the expected result. A future reference checker should reproduce every row.

### 8.1 Accepted

| # | Specs (essentials) | Usage types | Signature |
| --- | --- | --- | --- |
| A1 | `x = answer()`, `ensure x == 42` | `({ \| ∅ }) -> Int` | `answer : () -> Int` |
| A2 | `x = greet({ name: "Ada" })`, `ensure x == "Hello, Ada"` | `({ name: String \| ∅ }) -> String` | `greet : ({ name: String }) -> String` |
| A3 | A2, plus `p = some({ name: String, .. })`, `ensure greet(p) == "Hello, " + p.name` | A2's, and `({ name: String \| ρ̂ }) -> String` | `greet : ∀(R lacks name). ({ name: String \| R }) -> String`, printed `({ name: String, .. }) -> String` |
| A4 | `x = some(?A)`, `ensure identity(x) == x` | `(â) -> â` | `identity : (?X) -> X` |
| A5 | A4, plus `ensure identity(5) == 5` | `(â) -> â`, `(Int) -> Int` | `identity : (?X) -> X` |
| A6 | `ensure f('true) == 1`, `ensure f('false) == 0` | `({'true}) -> Int`, `({'false}) -> Int` | `f : ('true \| 'false) -> Int` |
| A7 | `x = some(?A)`, `ensure pick(x, x) == x`; and `y = some(?A)`, `z = some(?B)`, `ensure pick(y, z) == y` | `(â, â) -> â`, `(b̂, ĉ) -> b̂` | `pick : (?X, ?Y) -> X` |
| A8 | `xs = some([Int])`, `ensure length(reverse(xs)) == length(xs)`; and `ensure reverse([1, 2]) == [2, 1]` | `([Int]) -> [α]`, `([Int]) -> [Int]` | `reverse : ([Int]) -> [Int]` |

Notes:

- **A2 and A3** check against `person -> "Hello, " + person.name`. In A3 the parameter has a rigid row, and `[Proj]` unifies `{ name: α | ρ }` with `{ name: String | R̂ }` by setting `ρ := R̂`.
- **A5** shows a concrete usage compatible with a generic one.
- **A6** shows compatibility up to labels: each usage's `L⁻`, `{'true}` or `{'false}`, is included in the signature's set.
- **A7** shows a relationship relaxed by a spec that explicitly states the more general contract. The first usage is compatible with the second, with `X := â` and `Y := â`.
- **A8** shows a flexible variable acting as a wildcard: the length spec leaves the element type open, and the concrete spec, which is fully constrained, becomes the signature.

### 8.2 Rejected

| # | Situation | Stage | Reason |
| --- | --- | --- | --- |
| R1 | `ensure f(1) == 1`, `ensure f("a") == "a"` | Extraction | No usage is most general: "did you mean `some(?A)`?" |
| R2 | `greet({ name: "Ada" })` and `greet({ name: "Ada", age: 3 })` | Extraction | Neither record shape is compatible with the other |
| R3 | `ensure rev(xs) == xs` with `xs = some([?A])`, and `ensure rev(1) == 1` | Extraction | `(Int) -> Int` is not compatible with `([X]) -> [X]` |
| R4 | `x = some(?A)`, `ensure x == 1` | Elaboration | The spec binds rigid `â` to `Int` |
| R5 | Signature `identity : (?X) -> X`, implementation `x -> x + 1` | Checking | Rigid `X` cannot unify with `Int` |
| R6 | Only spec: `ensure cmp(1, 2) == 'lt`; implementation may return `'gt` | Checking | "`cmp` returns `'gt`, which no spec observes or handles" |
| R7 | Spec P: `ensure f(1) == 'foo`; spec Q: `case f(2) { 'a -> 1, 'b -> 2 }` | Extraction | `{'foo, 'a, 'b} ⊄ {'a, 'b}`: Q does not handle `'foo` |
| R8 | A field `helper` that no spec mentions | Pipeline | "no spec uses `helper`" |
| R9 | Signature `greet : ({ name: String }) -> String`, implementation uses `person.age` | Checking | The exact row `∅` cannot absorb `age` |
| R10 | `ensure pick(x, x) == x` with `x = some(?A)`, and `ensure pick(1, "a") == 1` | Extraction | The concrete usage contradicts the relationship stated by the generic spec: "spec P states that both parameters of `pick` have the same type, but spec Q calls it with `Int` and `String`" |
| R11 | `ensure const_(x, 1) == x` with `x = some(?A)`, and `ensure const_(1, y) == 1` with `y = some(?B)` | Extraction | Each usage is generic in a different parameter; neither is most general |
| R12 | Signature `g : ({ a: Int, ..?R }) -> { ..R }`; a local `h = v -> v.a + g(v).a` | Checking | `R` lacks `a`, so projecting `.a` from `g`'s result is a duplicate field (section 3.3) |
| R13 | Only spec: `x = some(?A)`, `y = f(x)`, with nothing constraining `y` | Extraction | "the most general use of `f` (spec P) does not constrain its result; add an `ensure` that does" |

## 9. Simplifications and open points

### 9.1 Simplifications in the core

- **Specs may not mention locals.** The design draft lets specs test locals without fixing their signatures. That creates a cycle: locals are inferred using field signatures, field signatures come from specs, and specs would use locals. A likely resolution is two-phase: treat local occurrences in specs like field occurrences during elaboration, then check each such usage against the local's inferred scheme after step 4 of the pipeline. The difficulty is that constraints flowing between a local and a field inside one spec would be missing in the first phase, which may leave field usages under-constrained.
- **Computed locals are monomorphic.** Only lambda bindings are generalized. Since the language is pure, generalizing computed bindings would also be sound; it is left out for simplicity.
- **Label sets in invariant positions are merged**, not compared by inclusion (section 3.2). Some programs that would be safe with full subtyping are rejected.
- **Only the file's fields are public.** Nested modules, whose fields would also need signatures, come with the module system.
- **The initialization-order check is assumed**, not specified here (section 4.2).

### 9.2 Decisions to confirm

- **Result labels must be observed.** By sections 6.3 and 7.2, an implementation may return only labels that some spec observes or handles (case R6). This makes specs exercise every returned label, but it also means a spec suite must mention each one.

### 9.3 Next extensions

In the order of the design draft's section 13.3:

1. **`$` escape checking**, including `$` in function types and second-class records.
2. **Initialization order**, specified as a check over the dependency graph of section 4.2.
3. **Operational semantics of `try`** and unwinding.

After those, the rules should be validated by a reference checker that reproduces the test cases of section 8.
