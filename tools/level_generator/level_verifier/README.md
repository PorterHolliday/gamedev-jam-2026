# Level Verifier

A command-line tool that verifies levels for the node-based number puzzle. Given
a level definition, it determines whether the level is solvable, produces
solutions in the game's step notation, and proves or disproves that every node
is required.

## Requirements

Python 3.8+, standard library only (no dependencies to install).

## Usage

```
python3 verify.py level.json                 # full report: solvable, solution, minimality
python3 verify.py level.json --solve          # first solution only
python3 verify.py level.json --all            # every distinct solution family found
python3 verify.py level.json --minimality     # leave-one-out table only
python3 verify.py level.json --bound 500 --max-latches 16
python3 verify.py level.json --bound -100,300 # asymmetric bound
python3 verify.py --test                      # run the regression corpus (spec section 8)
```

Exit codes: `0` solvable and minimal, `1` unsolvable (within the search bound),
`2` solvable but not minimal, `3` bad input (missing file, malformed JSON,
unparseable arguments).

## Level file format

```json
{
  "name": "Ratchet",
  "inputs":  { "I1": 2, "I2": 7 },
  "operations": {
    "P1": { "type": "sum" },
    "M1": { "type": "subtract" },
    "S1": { "type": "store" },
    "S2": { "type": "store" },
    "A1": { "type": "add", "value": -3 }
  },
  "outputs": { "O1": 1, "O2": 17, "O3": 19 }
}
```

Design-rule violations (1-4 inputs, 1-4 outputs, 1-6 operations, values in
-20..20, distinct input values, distinct output targets) are reported as
warnings, not rejected -- the solver will still run.

Sample levels for the regression corpus live in `levels/`.

## Honest incompleteness

Ratcheting through store latches makes the reachable value space unbounded in
principle, so the search is always bounded: a value bound (default `[-200,
200]`) prunes intermediate values, and a latch-count cap (default `12`) limits
how many store-latch events are explored. A negative result always names the
bound that produced it:

- `"proven unsolvable within bound [...]"` means the full state space inside
  that bound was explored -- there is genuinely no solution using those
  values.
- `"no solution found within bound [...] (search truncated by the latch cap)"`
  means the search hit the latch cap before exhausting the state space --
  a solution using more latches cannot be ruled out.

The tool never reports a bare "unsolvable." Minimality results inherit the
same caveat (each leave-one-out check is itself a bounded search, and is
flagged when its own search was truncated).

## How it works (brief)

Between store-latch events the live wiring is memoryless -- every node's
output is a pure function of the inputs and current store contents. So the
only durable state is what's latched in each store. The solver:

1. Searches over store-content states (BFS), where each transition is
   "latch some reachable value into store i," excluding store i's own current
   value as a source (this is what makes the single-store cycle in the spec's
   deadlock example unrepresentable, and is exactly the deadlock case 3 in the
   regression corpus tests for).
2. At each visited state, checks whether a single combinational network can
   produce every output target *simultaneously* -- this is stronger than each
   target being individually reachable, and is where the real search
   complexity lives (see `find_covering_networks` in `reach.py`).
3. Reconstructs one or more root-to-goal paths through the state graph for
   `--solve` / `--all`, and renders each as step notation, tracking port
   occupancy across the whole solution so redundant reconnects are skipped and
   auto-severs / store-latch auto-disconnects are annotated correctly.
4. For `--all`, collapses solutions that differ only by Sum port order or by
   the order independent wires are placed within a phase into a single
   "family" (see `notation.canonical_signature`).

Minimality (section 3) is a leave-one-out pass: delete each input/operation
node in turn and re-run solvability. Output nodes are never deletion
candidates -- they're the specification.

## Not implemented

Section 9's generator (delta-debugging / forward-enumeration level generation)
is not implemented in this pass -- the spec marks it a stretch goal, and the
solver core it depends on is what correctness hinges on. It would reuse
`solver.solve()` directly if you want it built next.

## Files

- `model.py` -- level data model, JSON loading, validation warnings.
- `reach.py` -- single-phase combinational reachability (value-only, and
  full network construction with provenance for step notation).
- `solver.py` -- outer search over store-content states.
- `notation.py` -- step-notation rendering and solution-family dedup.
- `minimality.py` -- leave-one-out analysis.
- `report.py` -- human-readable report assembly for each CLI mode.
- `verify.py` -- CLI entry point.
- `tests_corpus.py` -- the 5 hand-verified regression cases from spec
  section 8; run via `verify.py --test`.
- `levels/` -- the regression corpus as standalone level JSON files.
