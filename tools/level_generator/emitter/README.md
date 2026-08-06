# Level emitter

A deterministic path from an approved level JSON to a loadable, playable
`.tres`, replacing the hand-scripted transcription step formerly described in
`LEVEL_GENERATION_AGENT_INSTRUCTIONS.md` §19.

Implements CR-P1 through CR-P6 and CR-P8 of `LEVEL_PIPELINE_CHANGE_REQUESTS.md`.
CR-P7 (headless Godot import check) is not implemented — see *Not done* below.

## Usage

```bash
cd tools/level_generator

python3 emit.py levels/Challenge/challenge_4.json --category Challenge
python3 emit.py levels/*/*.json --force          # whole corpus
python3 emitter/test_emitter.py                  # test suite
python3 emitter/test_emitter.py --regenerate     # rewrite golden files
```

Output goes to `emitted/<Category>/` by default, **not** into the game project.
The phased `.tres` format is not readable by the shipped hint system until
CR-1…CR-6 of `HINT_SYSTEM_PHASE_CHANGE_REQUESTS.md` land; writing phased files
into `math-machine/Levels/LevelData/` before then leaves store levels
unplayable. Pass `--in-project` once the game side is ready.

`emit.py` never edits `Singletons/LevelManager/level_manager.tscn`. It prints
the exact `ExtResource` line and array entry to paste. Programmatic `.tscn`
editing is the one step here with a real corruption risk and no validation short
of opening the editor.

## Modules

| File | CR | Role |
|---|---|---|
| `project.py` | — | Reads UIDs, `NodeType` ordinals and engine limits **from the project at run time**. Nothing is hardcoded. |
| `ir.py` | — | The neutral intermediate representation. Depends on neither the solver's types nor Godot's. |
| `layout.py` | CR-P8 | §19.4 / §19.4a node array ordering. Returns the arrays *and* the `(type, slot)` map together. |
| `phases.py` | CR-P1 | Phase extraction from structured solver output, plus phase evaluation. |
| `ordering.py` | CR-P2 | Canonical intra-phase topological ordering. |
| `validate.py` | CR-P3 | All nine §19.13 checks, plus the required-store-state analysis. |
| `tres.py` | CR-P4 | Serialisation and the re-parser used for round-tripping. |
| `collapse.py` | §19.10 | Reduces families to distinct final configurations. |
| `replay.py` | CR-P1 | The §19.8 transcript replay, kept as a **test oracle** only. |
| `test_emitter.py` | CR-P6 | 34 tests: golden, cross-check, round-trip, invariant corruption, store-free regression. |
| `golden/` | CR-P6 | Checked-in expected output for all 25 levels. |

`project.py`, `ir.py` and `collapse.py` are helper modules not named in the CRs;
the CR-named files are all present and carry the behaviour their CRs specify.

Per §1 of the agent instructions, the emitter reads nothing under
`level_verifier/` other than `api.py`, and `generate.py` is untouched.

Two files under `level_verifier/` *were* changed, with the designer's explicit
go-ahead, and they are not part of the emitter: `solver.py` gained
`_latches_past_the_finish` (see the note below) and `tests_corpus.py` gained the
regression case that pins it. Both are documented here because they change what
the emitter is handed, not because the emitter depends on their internals.

## Two independent derivations

The production path reads the solver's structured output (`LatchPhase.built`,
`PlacedNode.inputs`). The oracle in `replay.py` re-parses the rendered English
transcript per §19.8. `test_dual_derivation` asserts they agree on **all 75
solution families across all 25 levels**. With no Godot in the loop, two
independent derivations agreeing is the strongest correctness signal available.

## Notes for whoever picks this up

**`generate.py`'s range defaults do not match §9's display ranges.** §9 is now
inputs −9..9, outputs −20..20, add values −9..9, and `emit.py` enforces exactly
that. `generate.py` hardcodes `(-9,20)`, `(-9,20)`, `(-9,9)`. Only the add-value
range agrees, and the other two diverge in opposite directions: the generator
samples inputs *wider* than is displayable (so it can produce levels `emit.py`
rejects) and enumerates output targets *narrower* (so it never proposes targets
in −20..−10). Generation runs should pass `--input-range=-9,9
--output-range=-20,20` until the generator's own defaults are aligned — which
is a change to generator internals, and therefore outside this tool's remit
per §1.

All 25 levels currently fit the display ranges with no per-level override, so
`test_emitter.RANGE_OVERRIDES` is empty. It is kept as the place to record one
if a level ever needs it, rather than burying the exception in a command line.

**§19.8's final phase needs pruning after all** — now fixed in the document.
§19.8 used to say to take the surviving wiring "with no pruning — minimality
guarantees every node is reachable from the outputs there". Minimality only
guarantees every node is needed *somewhere in the solution*, latch phases
included; it says nothing about the final configuration. A node whose only job
was to build a value into a store is idle at the end but its input wire is
still live, because latching severs the store's own input and nothing else.
`challenge_3` family 1 leaves `S1 → A1` behind this way, and the arithmetic
check cannot see it (A1 is single-input and *is* wired, and every output still
receives its target). The structured extraction prunes backwards from the
outputs and is correct; `replay.py` takes `prune_final=False` to reproduce the
old wording and see the difference.

**Solutions that latch past the finish are filtered in the solver.** A latch can
be causally "used" — its value wired straight to an output — and still be
redundant, because that value was already sitting on a live node that could have
been wired to the output directly. `store_4` had two families: reach `S1=9` and
wire `S1 → A1 → O1` (A1 computes 11), or do that *and* latch the 11 into `S2`
first, then read it back out. Every latch is used, so `_prune_dead_latches`
keeps the second one, but no player would do it.

`solver._latches_past_the_finish` drops these at source: if the store contents
at any point part-way through already make every output simultaneously
reachable, the rest is padding. This removed 5 of 75 corpus families —
`store_4` 2→1 and `store_5` 6→2 — and never the last representative of a
result, since the winning prefix state is itself in the search's
`winning_states` and generates its own shorter solutions. Regression case 6 in
`level_verifier/tests_corpus.py` pins it.

**Two store-free levels gain solution paths.** `add_value_4` (2 → 10) and
`sum_subtract_9` (10 → 11). The solver enumerates families exhaustively where
the shipped files were hand-transcribed with a subset. No shipped path is lost —
`test_store_free_matches_shipped` asserts containment, and
`test_store_free_no_new_paths` pins the exact set of levels that gain, so a
level that starts gaining paths for some other reason still fails.

**Output arrays get renumbered on every store-free level.** Shipped files list
outputs in JSON key order; §19.4 requires ascending by value. CR-P8 anticipates
this. The graphs are unchanged — only slot numbering — which is why the
store-free regression test compares by node *value* rather than by slot.

**Header UIDs are preserved when regenerating.** §19.11 says to omit `uid=` so
Godot assigns one on first import. That is right for a new file and wrong for
regenerating an existing one, since `level_manager.tscn` references levels by
uid and path. An existing target's uid is carried through verbatim; a new file
gets none.

**Don't compare structures containing frozensets by `repr()`.** `repr()` of a
frozenset is not order-stable across processes. An early version of the
store-free comparison did this and reported a different number of matching paths
depending on `PYTHONHASHSEED`. `notation._canon` exists for the same reason. The
suite passes under `PYTHONHASHSEED` 0, 1, 999 and 12345, and golden output is
byte-identical across them.

## Not done

**CR-P7 — headless Godot import check.** No Godot binary was available. The CR
marks it lowest priority and separable ("can be deferred indefinitely without
weakening the rest"), and warns that the Godot 4.7 invocation must be confirmed
against the documentation rather than assumed. Consequently **import remains
unverified** — the emitted resources have never been loaded by Godot. Everything
Python can check is checked; opening the project once and confirming the
resources load is still worth doing before building on them.

## Consequence for the agent instructions

Per the CR document: once this lands, §19.3 through §19.13 stop being a
procedure an agent executes and become this tool's specification. §19 should
shrink to the approval gate, how to invoke `emit.py`, how to read its report,
and the manual registration step. That edit is deliberately not part of this
work — make it once the tool's behaviour has settled, so the instructions
describe something real.
