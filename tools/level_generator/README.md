# Level Generator

`generate.py` inverts `level_verifier/`'s solver into a generator: it uses
`solve()` as a correctness oracle to produce new node-puzzle levels, rather
than just checking hand-made ones. `level_verifier/` itself is untouched
except for one new file, `level_verifier/api.py`, a re-export shim (see
"Touching the verifier" below).

## Usage

```
python3 generate.py deletion --outputs 1,17,19 --pool-inputs 4 --pool-ops 6 --seed 42
python3 generate.py enumerate --inputs 2 --ops "sum,subtract,store,store" --targets 3
python3 generate.py enumerate --inputs 2 --ops "sum,subtract,store,store" --targets 3 --exhaustive
```

Run `python3 generate.py deletion --help` / `enumerate --help` for the full
flag list. Both subcommands write one or more level JSON files (verifier-
loadable as-is) into `--out-dir` (default `levels/`, created if missing).

### Pipeline A: `deletion`

Delta-debugging shrink (spec section 9). Starts from a randomly over-
provisioned pool of inputs and operations against your fixed `--outputs`,
then greedily deletes nodes that don't break solvability. Minimal by
construction, one candidate per run. Reshuffle with a different `--seed` to
get a different minimal level from the same starting shape.

### Pipeline B: `enumerate`

Forward enumeration with derived targets (spec section 9). Fixes an
operation set (`--ops`) and input set (`--inputs`), computes what's reachable
(accounting for store ratcheting), and draws candidate output tuples from
that reachable set instead of guessing blind. Can emit many levels per run
(bounded by `--max-emit`, default 20).

- Default (fast-path) mode uses the spec's covering pre-filter: it discards
  the whole `(inputs, ops)` pairing outright if any single node can never be
  forced into a solution within the design value range -- this matches the
  spec's pseudocode literally, so a pairing that looks reasonable can still
  yield zero levels. If that happens, `--exhaustive` skips this filter and
  the fast-path covering check, and instead runs the real leave-one-out
  minimality check on every candidate target tuple.

## Value ranges

Three independently configurable ranges replace what used to be a single
`-20..20` "design range," so the generator can be retuned for a game's actual
display constraints without a source edit:

| Range | Flag | Default | Governs |
|---|---|---|---|
| Input | `--input-range` | `-9,20` | Where randomly-sampled starting inputs are drawn from (both pipelines); `--input-values` entries outside it are rejected. |
| Output | `--output-range` | `-9,20` | Pipeline A: `--outputs` values outside it are rejected outright, before any generation is attempted. Pipeline B: the *target-enumeration range* -- what output values get considered as candidates at all. |
| Add-value | `--add-value-range` | `-9,9` | Where randomly-sampled `add` op values come from; explicit `add:N` values in Pipeline B's `--ops` are validated against it too. |

**Decoupled from `--bound` on purpose.** `--bound` is the *solver's*
intermediate-value search space (how wide a value `solve()` is willing to
consider mid-network while proving solvability) -- a performance/completeness
knob, unrelated to what values are actually acceptable as inputs/outputs/add
values in the *emitted* level. Widening `--bound` gives the solver more room
to find a solution; it does not widen what gets sampled or what an emitted
level's node values can be. Earlier versions of this tool defaulted both to
the same numbers, which made them look coupled when they weren't -- they are
still two separate parameters now, just with defaults that no longer
coincide, and Pipeline B's target-enumeration loop now takes its range
directly from `--output-range` rather than a hardcoded literal.

**Validation, not silent failure.** `--outputs`, `--input-values`, and
explicit `add:N` values are all checked against their matching range up
front and rejected with a clear message (exit 1) if any value is out of
range -- previously an out-of-range value just came back "unsolvable" after
a full generation attempt, which read as an ordinary failure rather than the
input error it actually was.

**Negative lower bounds and argparse.** All four `lo,hi` flags (`--bound`
included) need `--flag=lo,hi` (with `=`) when `lo` is negative --
`--output-range -9,20` (space-separated) gets misparsed by argparse as an
unrecognized flag, because `-9,20` isn't a bare negative integer. `--output-range=-9,20`
works every time. This isn't new (`--bound` always had it); it's just far
more likely to come up now that three more flags default to a negative lower
bound.

## Design decisions left to my judgment

The build notes explicitly left several choices open. Here's what I picked
and why -- change any of these if they don't fit your use case.

**Output file naming/location.** `--out-dir levels/` (relative to wherever
you run the command from), one file per level named after `--name`
(default `generated`), with `_2`, `_3`, ... suffixes on collision. Pipeline
B's ranked survivors are automatically named `{name}_{rank}` before writing.

**Ranking / tier formula.** `score = solution_length + 2*latch_count + fam_term`,
where `fam_term = ±(family_count - 1)` -- negative by default (more distinct
solution families makes a level slightly *easier*/more forgiving to a
player, so it lowers the score), or positive with `--richer-families-are-harder`
(more families read as *harder*/richer instead). This is exactly the flag
the spec asks for rather than a hard-coded preference. `score` is then
bucketed into tiers 1-5 via `TIER_THRESHOLDS = [4, 8, 12, 17]` in
`generate.py` -- an arbitrary, documented default; tune to taste, nothing
upstream constrains it.

**Isomorphism filter.** No counterpart exists anywhere in `level_verifier/`
(the verifier's own symmetry logic compares solutions *within* one level, not
two different levels against each other), so this was written from scratch:
`canonical_signature()` reduces a level to `(input value set, output value
set, sorted (op type, op value) multiset)`. Two levels with the same
signature are considered isomorphic under node relabeling -- any two
sum/subtract/store nodes are interchangeable, two add nodes only if they
share the same value, matching how `notation._symmetry_classes` treats node
interchangeability within a single level's solution space.

**Flag names/shapes.** Follow the spec's CLI sketch where one was given;
invented reasonably elsewhere (`--pool-inputs`/`--pool-ops` for Pipeline A's
starting pool size, `--input-values`/`--ops` with an `add:5`-style value
syntax for Pipeline B's fixed shape, `--max-emit` as a safety valve on
Pipeline B's up-to-~100k-tuple search, `--input-range`/`--output-range`/
`--add-value-range` for the three display-constrained value ranges -- see
"Value ranges" above).

## Honest incompleteness

Every emitted level's `"generator"` block records the exact budget its
solvability/minimality claims were checked under -- never an unqualified
positive or negative:

- `bound`, `max_latches`: the `solve()` budget used.
- `input_range`, `output_range`, `add_value_range`: the three value ranges in
  force for this run (see "Value ranges" above) -- recorded for the same
  reason `bound` is: so a level file is self-describing about what
  constraints produced it, not just what the solver's search budget was.
- `minimal_within_bound`: true/false/**null**. Null means the final
  minimality sanity-check itself timed out (see below) -- the deletion
  loop's own bookkeeping still believes the level is minimal, but that belief
  is not independently confirmed.
- `minimality_rows_exhausted`: whether every leave-one-out `solve()` call
  underneath that minimality claim proved its result within `bound`/
  `max_latches`, or just ran out of search budget without finding a
  counterexample (still directionally correct for "required=True", but not a
  completeness proof).
- `solution_family_count` / `family_search_exhausted`: same idea, for the
  `find_all=True` family count. `null` family count means that search itself
  timed out; see `solver_timeout_hit`.
- `solver_timeout_hit`: true if *any* `solve()`/`minimality_report()` call
  anywhere in this run hit the generator's own wall-clock timeout (see
  below) -- a distinct, generator-owned incompleteness layer on top of
  `bound`/`max_latches`.

None of these ever collapse into a bare `true`/`false` claim without the
budget it rests on also being in the file. "Minimal by construction" always
means "minimal relative to this bound, this max_latches, and this wall-clock
patience" -- never unconditional.

## A real performance characteristic of the verifier, and how the generator works around it

`solve()`'s own default bound is `(-200, 200)`, documented as "generous
enough for anything hand-designed that fits the size constraints." That
assumption does not hold once you start *randomly sampling* pools instead of
hand-designing them: `reach.py`'s `reach_values()` is effectively unmemoized
for this purpose (its cache key includes the accumulated value pool, which
rarely repeats across a search), so a handful of `sum`/`subtract` ops on a
wide bound can blow up combinatorially while `solve()` tries to prove an
unsolvable candidate has no witness. This was confirmed directly during
development, not assumed: a random 4-input/6-op pool with several
combinational ops took **>20s** at the verifier's own default bound, was
still ~5s at `(-25, 25)`, and only became reliably fast once both the bound
was tightened *and* the number of combinational ops in the pool was capped.
Separately, adding just one more combinational op to an otherwise-identical
level pushed a single `solve()` call from ~2s to ~20s with barely any change
in the number of states explored -- the cost is in re-deriving
`reach_values()` per newly-discovered store state, and that cost scales with
combinational-op count much faster than linearly.

This is a real characteristic of the frozen verifier, not a generator bug,
and not something fixable by editing `solve()`/`reach.py` (which the project
notes explicitly rule out for working logic). Two independent, generator-
owned mitigations, both on by default and both overridable:

1. **A tighter default bound for generation**, `(-20, 20)` instead of the
   verifier's own `(-200, 200)` (`--bound` to override), and a cap of
   `DEFAULT_MAX_COMBINATIONAL_OPS = 3` combinational (add/sum/subtract) ops
   per randomly-sampled pool in Pipeline A (remaining pool slots are forced
   to `store`).
2. **A wall-clock timeout per verifier call** (`solve_with_timeout()` /
   `call_with_timeout()` in `generate.py`, default 8s, `--solve-timeout` to
   change or `0` to disable). This wraps `solve()` *and* `minimality_report()`
   calls uniformly via `SIGALRM` and treats a timeout as a third outcome,
   distinct from both `solvable=True` and `solvable=False` -- never a proof
   of anything, always recorded honestly (`solver_timeout_hit`) rather than
   silently reported as a negative.

If you deliberately want a richer combinational mix and are willing to wait
longer per candidate, raise `--pool-ops`/allowed op types and
`--solve-timeout` together; the generator will just take longer per attempt,
not produce wrong answers.

## Testing

- `python3 test_generate.py` -- the generator's own regression suite (not
  inside `level_verifier/`): Pipeline A output is always confirmed minimal by
  an independent `minimality_report()` call, generated levels always reload
  through `level_from_dict()` with zero design-constraint warnings, generated
  levels are always solvable per `solve()`, and the isomorphism filter is
  checked against known isomorphic/non-isomorphic pairs.
- `cd level_verifier && python3 verify.py --test` -- the verifier's own
  regression corpus. Unaffected by anything in this directory; re-run this
  after any change inside `level_verifier/` (there have been none beyond
  adding `api.py`, which nothing in `level_verifier/` imports).

## Touching the verifier

The only change inside `level_verifier/` is a new file, `api.py`, which
re-exports the handful of names `generate.py` needs (`Level`, `OpSpec`,
`solve`, `dedupe_families`, `render_solution`, `minimality_report`,
`reach_values`, ...) from the verifier's five different flat modules. It
changes no existing function signature, return shape, or solving/family/
minimality logic, and nothing inside `level_verifier/` imports it -- it's
purely a convenience seam for code outside the verifier's own directory.
`level_verifier/verify.py --test` was run before and after adding it and
reports `ALL TESTS PASSED` (5/5) both times.
