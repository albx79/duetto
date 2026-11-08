# Duetto: Formal Core

Nov 8, 2026 · @Alb

## 1. Purpose and scope

This document specifies the formal core of Duetto: the typing rules, spec elaboration, and extraction of public signatures from specs. It covers steps 1 and 2 of the design draft's section 13.3, typing and generalization and row unification, which every later feature depends on.

The core is a deliberately small fragment:

- **Included:** `Int`, `String`, and the bottom type `Never`; labels and label `case`; exact records and open rows; lists; lambdas and application; `==`; structs with fields, locals, and recursive groups; and spec entries with `some`, `?` variables, and `ensure`.
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
τ ::= Int | String | Never
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
- `Never` is the bottom type: no value has it. Since values are immutable, `[Never]` is a subtype of every list type, so `empty : () -> [Never]` can be used at any list type (section 3.2).
- Surface `{ f: T }` is `{ f: T | ∅ }`. In the core, `..` appears only inside `some(T)` in specs, where `{ f: T, .. }` is `{ f: T | ρ̂ }` with a fresh rigid row, and `{ f: T, ..?R }` is `{ f: T | ρ̂R }` (section 5.2). Flexible rows arise only from typing, as in `[Proj]`.
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

Built-in operators such as `+`, `++` and `length` are constants with fixed types in the initial environment `Γ₀`, for example `+ : (Int, Int) -> Int`, `++ : (String, String) -> String` and `length : ∀X. ([X]) -> Int`. Each operator has exactly one type: there is no overloading, since resolving an overload would be type-directed dispatch (design draft, section 6.2). String concatenation is therefore `++`, not `+`.

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

In the core, **spec entries appear only at file level**, and a spec body is not a struct in the sense of section 4: its bindings are typed by the spec rules of section 5.2, and are never generalized.

## 3. Typing expressions

Typing is constraint-based. The judgment `Γ ⊢ e : τ ⊣ C` says that `e` has type `τ` under the constraints `C`. Constraints are of two kinds:

- **Equations** `τ1 ~ τ2`, solved by unification (section 3.3).
- **Label inclusions** `L ⊆ ℓ` and `ℓ ⊆ L`, where `ℓ` is a label-set variable (section 3.2).

Unification and inclusion solving are standard, so the rules below list only what each form contributes.

### 3.1 Rules

```text
[Var]     Γ(x) = ∀X1...Xn, (R1 lacks Λ1)...(Rm lacks Λm). τ
          ⟹  Γ ⊢ x : fresh⁺(τ[Xi := αi, Rj := ρj])   (αi, ρj fresh;  Λ(ρj) = Λj)

[Int]     Γ ⊢ n : Int          [Str]  Γ ⊢ s : String

[Label]   ⟹  Γ ⊢ 'a : ℓ ⊣ {'a} ⊆ ℓ                        (ℓ fresh)

[List]    Γ ⊢ ei : τi   (each i)
          ⟹  Γ ⊢ [e1, ..., en] : [α] ⊣ τi ~ α             (α fresh; empty-origin if n = 0)

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

[Case]    Γ ⊢ e : τ    Γ ⊢ ei : τi    B = {'a1, ..., 'an}  (distinct)
          ⟹  Γ ⊢ case e { 'a1 -> e1, ... } : α
              ⊣ τ ~ ℓ, ℓ ⊆ B, τi ~ α                       (ℓ, α fresh)
```

`fresh⁺` replaces concrete label sets and `Never` by fresh variables according to polarity (section 3.2). It applies to every scheme in the environment: fields, built-in constants, and generalized locals.

Lambda parameters are monomorphic. A record literal is always exact; only rows introduced by `..` in specs, or by projection, are open.

**Branches of `case`.** In `[Case]`:

- **Duplicate labels are an error.** The branch labels `'a1, ..., 'an` must be distinct.
- **Extra branches are allowed.** The branches define the upper bound `L⁺(ℓ)`: the labels the code is prepared to handle. After solving, a branch whose label is not in the scrutinee's final lower bound `L⁻(ℓ)` is unreachable, and reported as a **warning**, not an error.

In specs, the branches of a `case` on a field's result contribute their labels to the field's signature, since result positions are positive (section 6.3).

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

α ~ ℓ      bind α := ℓ         (only a flexible α; α may stand for any type)

ℓ ~ τ      error, if τ is not a label set or a flexible type variable;
           in particular ℓ ~ â, as in  some(?A) == 'a,  is an error
```

**Polarity freshening.** Concrete label sets come from signatures, built-in constants, aliases such as `Bool`, and `some(T)`. They never take part in unification directly. Instead, when a scheme is instantiated, each concrete set and each `Never` is replaced by a fresh variable according to its **polarity**:

- A position is **positive** at the top of a type, and in list elements and record fields, which are covariant because values are immutable. The **parameters** of a function type flip polarity; its result keeps it.
- `fresh⁺` freshens with the polarity of each position; `fresh⁻` with the opposite polarity.

| At a position that is | a concrete set `L` becomes | `Never` becomes |
| --- | --- | --- |
| positive (a source of values) | a fresh `ℓ` with `L⁻(ℓ) = L` | a fresh `α` |
| negative (a sink of values) | a fresh `ℓ` with `L⁺(ℓ) = L` | `Never` |

This is the same mechanism as for literals, and it gives label sets their subtyping: a source of `{'a}` can flow into a sink of `{'a, 'b}`, since merging the two variables checks `{'a} ⊆ {'a, 'b}`. Likewise, a source of `Never` can be used at any type. Freshening is applied by `fresh⁺` in `[Var]` and `[Some]`, and by `fresh⁻` in `[Check]` (section 7.2), where the body of a field sees its parameters as sources and its result as a sink. Consequences:

- **Passing a label** `'a` to a parameter of signature type `{'a, 'b}` checks `{'a} ⊆ {'a, 'b}`.
- **Composing fields** works: with `g : () -> {'a}` and `f : ({'a, 'b}) -> Int`, `f(g())` checks `{'a} ⊆ {'a, 'b}`.
- **A `case` on a parameter** of signature type `L` with branches `B` checks `L ⊆ B`: exhaustiveness.
- **Returning** `'gt` where the signature's result is `{'lt, 'eq}` checks `{'gt} ⊆ {'lt, 'eq}` and fails (case R6).

The rule `ℓ ~ L` remains for completeness, but after freshening concrete sets do not reach the solver.

**Solutions.** At the end of solving, an unbound `ℓ` denotes its lower bound `L⁻(ℓ)`. In a spec, the pair `(L⁻(ℓ), L⁺(ℓ))` is what section 5.3 records as a label position, with `L⁺` absent when it is still `⊤`. These pairs are what extraction joins (section 6.3), which is how cases A6 and R7 are decided.

**No generalization.** Label-set variables are never generalized, in locals or elsewhere, which avoids bounded quantification. Signatures contain only concrete sets.

**One shared set of label variables per struct.** All uses of a local share its label-set variables, across the whole struct, including uses in different fields. These shared variables form one constraint system for all field checks (section 7.2), so a local helper's parameter set is the union of everything passed to it anywhere in the struct. This is conservative, and it means one field's use of a local can widen a label set that another field sees (case R18). Since bounds only grow and shrink monotonically, the result does not depend on the order in which fields are checked. Section 9.2 discusses relaxing this.

### 3.3 Row unification

Records unify field by field, with row tails absorbing missing fields. Write `F` for a set of fields.

```text
{ F | ∅ } ~ { F' | ∅ }    fields(F) = fields(F'); unify common fields

{ F | ρ } ~ { F' | ρ }    same tail: require fields(F) = fields(F'); unify common fields
                          (this also covers ρ ~ ρ, which needs no binding)

{ F | ρ } ~ { F' | r' }   r' ≠ ρ: unify common fields, then:
  if fields(F) ⊆ fields(F')     ρ := { F'∖F | r' }
  else if r' = ρ2 (flexible)    ρ := { F'∖F | ρ1 },  ρ2 := { F∖F' | ρ1 }   (ρ1 fresh)
  else                          error: F∖F' cannot be absorbed

{ F | ρ̂ } ~ { F' | ρ̂ }    fields(F) = fields(F'); unify common fields
```

The same-tail rule prevents the known non-termination case, where a tail would be rebound against itself (Leijen, *Extensible records with scoped labels*).

The third rule also applies symmetrically, with the sides swapped. Any other combination is an error.

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

Locals, and the fields of **nested** record literals, are typed in dependency order, not textual order. Nested fields may refer to each other, like locals (design draft, section 3.5), so they are treated the same way:

1. Build the dependency graph of the struct's locals and of the fields of its nested record literals: `x` depends on `y` if `y` occurs in `x`'s right-hand side.
2. Compute its strongly connected components, and type them in topological order.
3. Within a component, each name `x` gets a fresh `αx`; the right-hand sides are typed with those assumptions, and `Γ ⊢ ex : τx` adds `αx ~ τx`.
4. After solving the component, **lambda locals are generalized** over the type and row variables that are not free in `Γ`. Computed locals stay monomorphic, and label-set variables are never generalized (section 3.2).
5. **Fields of nested record literals are never generalized**, even when their right-hand side is a lambda: a record type has no `∀` (section 2.1), so a polymorphic field could not appear in the type of the record that contains it. Within the record, such a field is used at one type (case R19). Polymorphic fields of records, and of imported modules, wait for rank-2 polymorphism (design draft, sections 3.1 and 13.4).

The components also determine function identity: a closure's identity includes the external captures of every component it can reach (design draft, section 5.1).

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

Nested structs follow the same rules. Only the fields of the **file** are public, so only they receive signatures from specs; fields of nested record literals are inferred, as in section 4.2.

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
[Some]     T elaborated with:  ?A ↦ â (fresh rigid),  ..?R ↦ ρ̂R,  .. ↦ fresh rigid row
           ⟹  binding x = some(T)  gives  x : fresh⁺(T̂)

[Let]      Γspec ⊢ e : τ   ⟹   binding x = e  gives  x : τ   (monomorphic)

[Ensure]   Γspec ⊢ e : τ
           ⟹  ensure e  adds  τ ~ ℓ,  ℓ ⊆ {'true, 'false}
```

**Lacks sets of rigid rows.** A rigid row named by `?R` may appear several times in one spec, next to different fields, as in `some({ ..?R })` followed by `some({ id: Int, ..R })`. Its lacks set is the **union** of the fields next to it in every occurrence within the spec, computed before typing the body: here `Λ(ρ̂R) = {id}`.

A `?A` is rigid in the spec that introduces it: the spec states a fact for every `A`. Later occurrences of `A` in the same spec refer to the same `â`. An anonymous `..` inside `some` is also rigid, since `some({ name: String, .. })` means "any record that has `name`." Spec bindings, including lambda bindings, are monomorphic: `[Let]` takes precedence over the generalization of section 4.2.

### 5.3 Solving and usage types

After typing the body, the spec's constraints are solved. Then:

1. **Rigid variables must stay rigid.** If solving would bind `â` or `ρ̂` to anything other than itself, the spec is ill-typed. For example, `x = some(?A), ensure x == 1` treats `A` as `Int`, and is reported as such.
2. **Each usage `(f, αk)` yields the usage type** `Uk = solve(αk)`. Rigid variables remain in `Uk`.
3. **Variables from empty list literals default to `Never`.** `[List]` with no elements marks its fresh element variable as **empty-origin**, and the mark is kept when variables are merged. A flexible variable that is empty-origin and occurs only in positive positions of `Uk` becomes `Never`: the spec observed an empty list there, and `Never` is the least type consistent with that. For example, `ensure empty() == []` gives `() -> [Never]`. No other variable is defaulted: a position the spec merely ignores, such as the elements of a result passed only to `length`, stays flexible, and section 6.4 says when that is allowed. A field whose specs only ever observe an empty result still gets `[Never]`, so an implementation that can return elements fails its check (case R20). That diagnostic must name the cause: "`keep` returns `Int` elements, but its specs only observed an empty list; add a spec that observes a non-empty result."
4. **Open rows in positive positions are closed.** A flexible row that occurs only in positive positions of `Uk` becomes `∅`: the record consists of the fields the spec observed. This happens whenever a spec projects from a result, as in `c.compare(...)` with `c = mk()`, since `[Proj]` leaves the rest of the row open. Without this step, no spec could fix the exact type of a record result whose fields are functions, because such a result cannot be compared with a record literal. It is the record counterpart of the label rule of section 6.3, decided in section 9.2: a result contains only what specs observe, so an implementation that returns a field no spec observes fails its check (case R22). Flexible rows in negative positions are not closed, and remain unconstrained. Rigid rows, from `..` in `some`, are never closed.
5. **Label-set variables keep their bounds.** A label position in `Uk` is a pair `(L⁻, L⁺)`: the labels that flow into that position, and the labels the spec handles there (with `L⁺` absent if it is still `⊤`). A label position with neither bound counts as unconstrained.

The outputs of a spec, as far as the core is concerned, are its usage types. Runtime execution of specs is unchanged from the design draft.

## 6. Extraction by anti-unification

For each field `f`, extraction takes all usage types `U1, ..., Un` of `f`, from every spec, and produces either a signature `σf` or a conflict. Rigid variables from different specs are distinct.

**Reading order.** The signature is defined by section 6.4, with label sets joined as in 6.3. Sections 6.1 and 6.2 describe anti-unification, which is used only to locate disagreements for diagnostics. Soundness does not rest on this section at all: after extraction, every spec is re-typed against the signatures (section 7.4).

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

- **Negative positions** (parameters, where specs supply values): `S = ⋃ L⁻i`. Only labels that specs actually pass count. A spec's own `case` on a value it also passes to `f` says nothing about `f`, so its upper bound is ignored here.
- **Positive positions** (results, and parameters of callbacks): `S = ⋃ L⁻i ∪ ⋃ L⁺i`: every label a spec observes, and every label some spec is prepared to handle. **Check:** for each usage with an upper bound, `S ⊆ L⁺i`; otherwise that spec handles too few labels: "spec Q's `case` does not handle `'foo`, which reaches this position in spec P."
- A concrete set from `some(T)` contributes its labels as `L⁻`, since generated values are sources.

**Typos in handled labels.** Because handled labels contribute to `S` at positive positions, a misspelled branch in a spec's `case` on a result, such as `'bogus` for `'gt`, enters the signature. This is accepted deliberately: every other `case` on the same result, in other specs through the check `S ⊆ L⁺` and in production code through exhaustiveness, then fails to cover `'bogus`, so the typo is reported at nearly every point of use except the one where it was made.

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

**Compatibility.** `U ⊑ σ` holds if there is **one consistent substitution** for `σ`'s generalization variables, types for `X` and rows for `R` respecting their lacks sets, under which `U` matches `σ` position by position:

- `U`'s rigid variables are constants. A flexible variable in `U` matches anything, but every occurrence of the same variable must match consistently: `([β]) -> [β]` does not match `([Int]) -> [String]`.
- At a **label position** with signature set `S`: in a negative position, `L⁻ ⊆ S`; in a positive position, `L⁻ ⊆ S ⊆ L⁺` (with `L⁺` omitted when absent).
- At a **positive** position, `Never` in `U` matches any type, since `Never` is the bottom type.

If several usages qualify as `U*`, their candidate signatures are equal up to renaming, so the choice does not matter.

Compatibility is the rule for **choosing** the signature, and for diagnostics. It is not the soundness guarantee: usages in one spec share variables, and checking them one at a time can miss a spec that is ill-typed as a whole. That is caught by re-typing every spec in `Γsig` (section 7.4).

**Unconstrained positions.** Flexible variables are allowed in usages other than `U*`, where they act as wildcards. If the only candidate for `U*` leaves a position unconstrained, extraction fails: "the most general use of `f` (spec P) does not constrain its result; add an `ensure` that does." Only empty-origin variables have been defaulted to `Never` (section 5.3), so a result that a spec passes only to `length`, for example, is still unconstrained and reported (case R16). If a function's **entire result** would default to `Never`, giving a function that never returns, it is reported with the same message instead, since that is not what the spec meant.

Anti-unification (6.1) is used for **diagnostics**: when usages conflict, the positions where their tuples disagree show where the specs differ. The report names those specs, and suggests `some(?A)` where a concrete usage was probably meant to be generic.

Signatures are printed with `?` on the first occurrence of each variable, as in `identity : (?X) -> X`.

### 6.5 Properties

- **Every usage is compatible with `σf`** (`U ⊑ σf`), by definition, and **every spec is well-typed against all signatures**, by the re-check in section 7.4. The second property is the soundness guarantee.
- **Generality is never invented.** The signature's type and row structure is always exactly what one spec wrote, never a combination of what several specs wrote. Only label sets are joined across specs.
- **Holes are never guessed.** The usage that becomes the signature is fully constrained. The only defaulting is to `Never`, only where a spec observed an empty list, and the closing of open rows in positive positions to the fields a spec observed (section 5.3).
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
          C, τ ~ fresh⁻(τf[Xi := x̂i, Rj := r̂j])  solvable   (x̂i, r̂j fresh rigid;  Λ(r̂j) = Λj)
          no x̂i or r̂j escapes into a variable free in Γsig
          ⟹  f: e  is well-typed
```

Each field is checked in **its own constraint system** for type and row variables, after the locals have been inferred. Label-set variables of locals are the exception: they are shared by all field checks, as section 3.2 states. The **escape check** matters because a monomorphic computed local has flexible variables free in `Γsig`: if checking `f` unified one of them with `f`'s rigid `x̂`, that rigid variable would leak into every other use of the local.

The generalization variables become rigid, so the implementation must work uniformly for every instance: it cannot use an `X` as an `Int`. Label sets and `Never` in `σf` are freshened with flipped polarity (section 3.2):

- **In parameter positions**, the body sees a source with `L⁻ = S`, so every label in the signature's set must be handled. A `case` with branches `B` on such a parameter requires `S ⊆ B`.
- **In result positions**, the body sees a sink with `L⁺ = S`, so it may produce only labels in `S`. Producing `'gt` where the signature says `{'lt, 'eq}` is an error: "`f` returns `'gt`, which no spec observes or handles."

The second rule follows from section 6.3, and matches the design draft's intent that every label of a public interface is exercised by some spec. It applies to every predicate implemented with `==`, whose result has the lower bound `{'true, 'false}`: some spec must observe each label (cases A12 and R17).

This is how the design draft's rule that "an implementation cannot strengthen its required input shape or change its return type" is enforced: the implementation's type must match the signature exactly, up to the rigid variables.

### 7.3 Nested records

Fields of nested record literals, including fields of record values returned by functions, are inferred together with locals (section 4.2). Only the file's own fields are public and receive signatures.

### 7.4 Pipeline

1. **Elaborate every spec** (section 5), producing usage types. Ill-typed specs, including rigid-variable violations, are reported here.
2. **Every field must have at least one usage.** A field no spec mentions has no signature: "no spec uses `f`."
3. **Extract a signature for every field** (section 6). Conflicts are reported here.
4. **Re-type every spec in `Γsig`**, instantiating `σf` at each field use with `[Var]`. This is the soundness step: it catches specs whose usages are each compatible but which are ill-typed together, such as `ensure g(f(1)) == 4` with `f : (Int) -> String` and `g : (Int) -> Int` (case R14).
5. **Infer locals and check fields** in `Γsig` (sections 4.2 and 7.2). Diagnostics for a field that fails its check name the specs whose usages produced the conflicting part of its signature.
6. **Run specs**, as in the design draft. This step is outside the core.

## 8. Test cases

These cases pin down the rules. Each lists the usage types that elaboration produces and the expected result. A future reference checker should reproduce every row.

### 8.1 Accepted

In usage types, a label position is written as its bounds: `(L⁻, L⁺)`, with `⊤` for an absent upper bound.

| # | Specs (essentials) | Usage types | Signature |
| --- | --- | --- | --- |
| A1 | `x = answer()`, `ensure x == 42` | `({ \| ∅ }) -> Int` | `answer : () -> Int` |
| A2 | `x = greet({ name: "Ada" })`, `ensure x == "Hello, Ada"` | `({ name: String \| ∅ }) -> String` | `greet : ({ name: String }) -> String` |
| A3 | A2, plus `p = some({ name: String, .. })`, `ensure greet(p) == "Hello, " ++ p.name` | A2's, and `({ name: String \| ρ̂ }) -> String` | `greet : ∀(R lacks name). ({ name: String \| R }) -> String`, printed `({ name: String, .. }) -> String` |
| A4 | `x = some(?A)`, `ensure identity(x) == x` | `(â) -> â` | `identity : (?X) -> X` |
| A5 | A4, plus `ensure identity(5) == 5` | `(â) -> â`, `(Int) -> Int` | `identity : (?X) -> X` |
| A6 | `ensure f('true) == 1`, `ensure f('false) == 0` | `(({'true}, ⊤)) -> Int`, `(({'false}, ⊤)) -> Int` | `f : ('true \| 'false) -> Int` |
| A7 | `x = some(?A)`, `ensure pick(x, x) == x`; and `y = some(?A)`, `z = some(?B)`, `ensure pick(y, z) == y` | `(â, â) -> â`, `(b̂, ĉ) -> b̂` | `pick : (?X, ?Y) -> X` |
| A8 | `xs = some([Int])`, `ensure length(reverse(xs)) == length(xs)`; and `ensure reverse([1, 2]) == [2, 1]` | `([Int]) -> [α]`, `([Int]) -> [Int]` | `reverse : ([Int]) -> [Int]` |
| A9 | `ensure empty() == []` | `() -> [Never]` | `empty : () -> [Never]` |
| A10 | Signatures `g : () -> 'a` and `f : ('a \| 'b) -> Int`; production code `h: () -> f(g())` |  | `f(g())` checks `{'a} ⊆ {'a, 'b}` |
| A11 | `x = 'a`, `y = case x { 'a -> 1, 'b -> 2 }`, `ensure f(x) == 1`; implementation `x -> case x { 'a -> 1 }` | `(({'a}, {'a, 'b})) -> Int` | `f : ('a) -> Int`; the implementation is accepted |
| A12 | `ensure same(1, 1) == 'true`, `ensure same(1, 2) == 'false`; implementation `(a, b) -> a == b` | `(Int, Int) -> ({'true}, ⊤)`, `(Int, Int) -> ({'false}, ⊤)` | `same : (Int, Int) -> 'true \| 'false`; the implementation is accepted |
| A13 | `c = mk()`, `ensure c.compare(1, 1) == 'eq`, `ensure c.compare(1, 2) == 'lt`; implementation `() -> { compare: (a, b) -> case a == b { 'true -> 'eq, 'false -> 'lt } }` | `() -> { compare: (Int, Int) -> ({'eq, 'lt}, ⊤) \| ∅ }` | `mk : () -> { compare: (Int, Int) -> 'eq \| 'lt }`; the implementation is accepted |

Notes:

- **A2 and A3** check against `person -> "Hello, " ++ person.name`, using `++ : (String, String) -> String`. In A3 the parameter has a rigid row, and `[Proj]` unifies `{ name: α | ρ }` with `{ name: String | R̂ }` by setting `ρ := R̂`. With `+ : (Int, Int) -> Int`, the only addition operator, both would be rejected, since `+` is not overloaded for strings.
- **A5** shows a concrete usage compatible with a generic one.
- **A6** shows the label join: either usage supplies the structure, and the negative position's set is `{'true} ∪ {'false}`.
- **A7** shows a relationship relaxed by a spec that explicitly states the more general contract. The first usage is compatible with the second, with `X := â` and `Y := â`.
- **A8** shows a wildcard: the length spec leaves the result's element type flexible, since it observed no empty list there (section 5.3), so the concrete spec becomes the signature. Alone, the length spec would be rejected (case R16).
- **A9** shows a polymorphic constant stated honestly: the spec observed an empty list, so the element type defaults to `Never`, and `[Never]` is usable at any list type, by freshening at `[Var]`.
- **A10** shows label subtyping through freshening, which plain unification of concrete sets would reject.
- **A11** shows that a spec's own `case` does not leak into a parameter's signature: the upper bound `{'a, 'b}` is ignored at a negative position.
- **A12** shows a predicate: the body's `==` has the lower bound `{'true, 'false}`, and the two specs together observe both labels.
- **A13** shows a field that returns an interface value. Projecting `c.compare` leaves `mk`'s result row open, and since it occurs only in a positive position, it is closed to `{ compare }` (section 5.3). The labels returned by `compare` are in a positive position too, so they follow the same rule as a plain result, and the spec observes both labels the implementation can return (design draft, section 12.3).

### 8.2 Rejected

| # | Situation | Stage | Reason |
| --- | --- | --- | --- |
| R1 | `ensure f(1) == 1`, `ensure f("a") == "a"` | Extraction | No usage is most general: "did you mean `some(?A)`?" |
| R2 | `greet({ name: "Ada" })` and `greet({ name: "Ada", age: 3 })` | Extraction | Neither record shape is compatible with the other |
| R3 | `ensure rev(xs) == xs` with `xs = some([?A])`, and `ensure rev(1) == 1` | Extraction | `(Int) -> Int` is not compatible with `([X]) -> [X]` |
| R4 | `x = some(?A)`, `ensure x == 1` | Elaboration | The spec binds rigid `â` to `Int` |
| R5 | Signature `identity : (?X) -> X`, implementation `x -> x + 1` | Checking | Rigid `X` cannot unify with `Int` |
| R6 | Only spec: `ensure cmp(1, 2) == 'lt`; implementation may return `'gt` | Checking | "`cmp` returns `'gt`, which no spec observes or handles" |
| R7 | Spec P: `ensure f(1) == 'foo`; spec Q: `ensure case f(2) { 'a -> 1, 'b -> 2 } == 1` | Extraction | `{'foo, 'a, 'b} ⊄ {'a, 'b}`: Q does not handle `'foo` |
| R8 | A field `helper` that no spec mentions | Pipeline | "no spec uses `helper`" |
| R9 | Signature `greet : ({ name: String }) -> String`, implementation uses `person.age` | Checking | The exact row `∅` cannot absorb `age` |
| R10 | `ensure pick(x, x) == x` with `x = some(?A)`, and `ensure pick(1, "a") == 1` | Extraction | The concrete usage contradicts the relationship stated by the generic spec: "spec P states that both parameters of `pick` have the same type, but spec Q calls it with `Int` and `String`" |
| R11 | `ensure const_(x, 1) == x` with `x = some(?A)`, and `ensure const_(1, y) == 1` with `y = some(?B)` | Extraction | Each usage is generic in a different parameter; neither is most general |
| R12 | Signature `g : ({ a: Int, ..?R }) -> { ..R }`; a local `h = v -> v.a + g(v).a` | Checking | `R` lacks `a`, so projecting `.a` from `g`'s result is a duplicate field (section 3.3) |
| R13 | Only spec: `x = some(?A)`, `y = f(x)`, with nothing constraining `y` | Extraction | "the most general use of `f` (spec P) does not constrain its result; add an `ensure` that does" |
| R14 | Spec P: `ensure f(1) == "one"`; spec Q: `ensure g(2) == 4`; spec R: `ensure g(f(1)) == 4` | Re-check | Each usage is compatible, but re-typing R in `Γsig` passes `f`'s `String` to `g`'s `Int` |
| R15 | `x = some(?A)`, `ensure x == 'a` | Elaboration | A label set cannot unify with the rigid `â` (section 3.2) |
| R16 | Only spec: `xs = some([Int])`, `ensure length(reverse(xs)) == length(xs)` | Extraction | The result's element type is flexible, not empty-origin, so it is not defaulted: "the most general use of `reverse` does not constrain its result". Under the earlier rule, this produced `([Int]) -> [Never]`, which every real implementation would then fail |
| R17 | Only spec: `ensure same(1, 1) == 'true`; implementation `(a, b) -> a == b` | Checking | The signature is `(Int, Int) -> 'true`, and `==` can produce `'false`: "`same` returns `'false`, which no spec observes or handles" |
| R18 | Computed local `v = 'a`; field `f: () -> v` with `f : () -> 'a`; field `g: () -> length([v, 'b])` with `g : () -> Int` | Checking | `v`'s label variable is shared by both field checks (section 3.2). Checking `g` merges it with `'b`, so `f` would return `'b`: "`f` returns `'b`, which no spec observes or handles", caused by `g` |
| R19 | Local `r = { id: x -> x, both: () -> { a = id(1), b = id("s"), <<a } }` | Checking | `id` is a field of a nested record, so it is not generalized (section 4.2): it cannot be used at both `Int` and `String` |
| R20 | Only spec: `xs = some([Int])`, `ensure keep(xs) == []`; implementation `xs -> xs` | Checking | The result's element type is empty-origin, so the signature is `([Int]) -> [Never]`, and `Int` cannot unify with `Never`. The diagnostic says the specs only observed an empty list (section 5.3) |
| R21 | Only spec: `c = mk()`, `ensure c.compare(1, 2) == 'lt`; implementation as in A13 | Checking | The signature is `() -> { compare: (Int, Int) -> 'lt }`, and the body can return `'eq`: "`mk`'s `compare` returns `'eq`, which no spec observes or handles" |
| R22 | Specs as in A13; implementation `() -> { compare: (a, b) -> ..., name: "by value" }` | Checking | `mk`'s result row was closed to the observed field `compare` (section 5.3), so the extra field `name` cannot be absorbed: "`mk` returns the field `name`, which no spec observes" |

## 9. Simplifications and open points

### 9.1 Simplifications in the core

- **Specs may not mention locals.** The design draft lets specs test locals without fixing their signatures. That creates a cycle: locals are inferred using field signatures, field signatures come from specs, and specs would use locals. With the re-check of section 7.4, a likely resolution is to let specs mention locals during elaboration as wildcards, and to type those uses only in the re-check, once locals are inferred.
- **Computed locals are monomorphic.** Only lambda bindings are generalized. Since the language is pure, generalizing computed bindings would also be sound; it is left out for simplicity.
- **Label-set variables are not generalized** (section 3.2), so a local helper's label sets are shared by all its uses, across all field checks.
- **Fields of nested records are monomorphic** (section 4.2), since record types have no `∀`.
- **Only the file's fields are public.** Nested modules, whose fields would also need signatures, come with the module system. The design draft's section 13.1 discusses how imported modules are typed.
- **The initialization-order check is assumed**, not specified here (section 4.2).

### 9.2 Decisions and open points

- **Result fields must be observed (decided).** An open row in a positive position is closed to the fields a spec observed (section 5.3, case R22). This follows the label rule below: a public result contains only what specs observe. It is needed because no other spec form can fix the exact type of a record result whose fields are functions.
- **Result labels must be observed (decided).** By sections 6.3 and 7.2, an implementation may return only labels that some spec observes or handles (cases R6 and R17). This is kept, because it is what makes every label of a public interface exercised by some spec. Its cost falls on every predicate implemented with `==`: a spec suite must observe both `'true` and `'false` (case A12). A spec suite that tests only the positive case of a predicate is incomplete, so the cost is accepted. The same holds for fields that return interface values, such as an ordering: every label its functions return must be observed (cases A13 and R21). No adjustment of the rule is needed for them, only guidance (design draft, sections 10.4 and 12.3). One alternative was considered and not adopted: counting the observations of law specs, which check orderings for every label. Law specs do not call the field, though, so they produce no usage of it.
- **Label sets shared between field checks (open).** Section 3.2 shares a local's label-set variables across all field checks, so one field's use of a local can widen a label set that another field sees (case R18). That is sound but not modular, and the resulting errors appear far from their cause. The options:
  1. **Keep sharing**, the current rule. Simple and sound; diagnostics must name both fields.
  2. **Copy per field**: each field check uses its own copy of the locals' label-set variables, with their bounds. Field checks become independent, but a local's label sets still mix all uses within one field.
  3. **Copy per use**: treat each local, once inferred, as a scheme whose label-set variables and bounds are copied at every use, in the style of HM(X) constraint copying. Each use is independent, and since locals' types never appear in signatures, no bounded quantification syntax is needed.

  Recommendation: option 3, after a soundness argument for copying bounds. It removes R18's action at a distance, and it subsumes option 2. Until then, option 1 holds.
- **A change from the earlier extraction rule.** The design draft's earlier anti-unification rule accepted R11, since each variable of the generalization `(X, Y) -> X` came from some `?` variable. The core rejects it under the "most general usage" rule. This is a deliberate change of meaning, not just added precision, and the design draft has been updated to match.

### 9.3 Next extensions

In the order of the design draft's section 13.3:

1. **`$` escape checking**, including `$` in function types, second-class records, and the polymorphic payloads proposed in the design draft's section 12.6.
2. **Initialization order**, specified as a check over the dependency graph of section 4.2.
3. **Operational semantics of `try`** and unwinding.

After those, the rules should be validated by a reference checker that reproduces the test cases of section 8.

**Cases the `$` and `try` step must reproduce.** These are stated informally in the design draft and must become rules and test cases of that step:

| # | Situation | Expected |
| --- | --- | --- |
| T1 | The design draft's section 11.1 example: one double with a `returns` stub and a `raises` stub, two `try`s whose handlers use `e.path` | Accepted: `read_file : ({ read_text: (String, $ ({ path: String }) -> Never) -> String }, String, $ ({ path: String }) -> Never) -> String` |
| T2 | As T1, but the success stub and the raising stub are in two separate specs | Rejected at extraction: neither use is fully constrained, since one leaves `read_text`'s result open and the other its raiser's type |
| T3 | As T1, but the double raises `$nf({ path: "a.cfg", line: 3 })` | Under the current rule, rejected when checking `read_file`: its raiser takes `{ path: String }`, from the handlers, but is passed where `{ path: String, line: Int }` is expected. **Under the proposal, accepted**: the handlers give `∀R. ({ path: String, ..R }) -> Never`, which is instantiated with `R := { line: Int }` |
| T4 | A `raises` stub whose raiser is not bound by the same stub, or a response that mentions an outer `$`-name | Compile error (design draft, section 11) |
| T5 | A double for a higher-order function, `fold(xs, $f) returns $f(1)` | Accepted: `$f(1)` is an ordinary call, so `$f`'s result is not `Never` |
| T6 | `$h -> $h.num(n)` returned from a function, and `map(xs, $f)` collecting `$f(x)` | Accepted: call results are first-class (design draft, section 9.1) |
| T7 | `$times_two = x -> x * 2` passed to `map` in a spec | Accepted, and establishes `map`'s parameter as a `$`-parameter (design draft, section 12.4) |
| T8 | A recursive `$`-local `$go = x -> ... $go(...)`, and a plain sibling that mentions it | The `$`-local is accepted; the plain sibling is an error (design draft, section 3.5) |
| T9 | A handler that ignores its payload, with a double that raises `{ path: "a.cfg" }` | Under the current rule, rejected when checking: the payload is `{}`. **Under the proposal, accepted**: the handler gives `∀R. ({ ..R }) -> Never` (design draft, section 12.6) |
| T10 | Under the proposal: a production caller whose handler compares its payload with an exact record, `not_found(e) -> case e == { path: "a" } { ... }`, passes its raiser to `read_file` | Rejected: the raiser is monomorphic, and `read_file`'s parameter requires a raiser polymorphic in the rest of the payload |