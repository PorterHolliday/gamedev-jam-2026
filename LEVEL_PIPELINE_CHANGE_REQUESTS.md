# Level Pipeline — Change Requests

Build a deterministic path from a level JSON to a loadable, playable `.tres`,
replacing the hand-scripted transcription step currently described in
`tools/level_generator/LEVEL_GENERATION_AGENT_INSTRUCTIONS.md` §19.

These are Python tooling change requests. They do not touch game code, and do
not block the game-side work in `HINT_SYSTEM_PHASE_CHANGE_REQUESTS.md`.

---

## 0. Why this exists

§19 of the agent instructions is declared "pure transcription — neither the
tools' judgment nor yours." It is nonetheless executed by an agent writing a
throwaway script each session, from prose, untested.

That was tolerable when the transformation was "replay a transcript, keep the
surviving wires." Under phased solution paths it is: parse solver output →
snapshot at each latch → prune by backward reachability → assemble phases →
topologically order each phase → compute per-phase required store state →
validate five structural invariants → serialise `.tres` with Godot's
default-omission rules. Several hundred lines that must be exactly right, with
no test coverage and no memory between sessions.

Evidence that this is the right thing to automate: the instructions document
carried a wrong script filename (`StoreValueStepData.gd`, which does not exist)
and a wrong registration procedure (a per-level `.tscn` that no longer exists)
for an unknown number of sessions. Neither would survive a single round-trip
test.

### Relationship to §1 of the agent instructions

§1 forbids the agent from building, modifying, or reasoning about the
**generator's or verifier's internals**. This work adds a *third* tool alongside
them, consuming their output. `level_verifier/api.py` already exists as a
sanctioned re-export shim for exactly this kind of consumer. No file under
`level_verifier/` other than `api.py` is read or changed.

### Scope boundary

The emitter handles everything mechanical. It does **not** choose levels, assign
tiers, or decide what is interesting — that stays with the curating agent (§16
of the instructions). The emitter's contract is: given an approved level JSON,
produce a correct `.tres` or fail loudly.

---

## CR-P1 — Phase extraction from structured solver output

**New file:** `tools/level_generator/emitter/phases.py`
**Depends on:** nothing

### Behaviour

Consume the solver's **structured** output via `level_verifier/api.py` —
`Solution`, `LatchPhase`, `FinalPhase`, `PlacedNode` — not the rendered text
transcript.

This is the central design decision of the pipeline. `render_solution` in
`notation.py` emits deltas: it suppresses any wire already correct from an
earlier phase. A phase needs a **snapshot** — every wire live at its latch.
Reconstructing snapshots by re-parsing delta text is possible but is exactly the
error-prone step being eliminated. `LatchPhase.built` plus `PlacedNode.inputs`
gives the network directly.

For each `LatchPhase`, produce the set of wires reachable by walking backwards
from `assignment['_latch']` through `built`, terminating at sources (level
inputs, and stores holding their pre-phase values per `sources_for_state`), plus
the latch wire itself. Record the phase's `(store_id, value)` terminator.

For `FinalPhase`, produce the wires reachable backwards from every entry in
`assignment`, unpruned beyond that reachability. No terminator.

Drop any latch phase whose store is never subsequently read — neither as a
source in a later phase nor in the final phase.

Emit a neutral intermediate representation (node ids, ports, per-phase wire
sets, terminators) independent of both the solver's types and Godot's.

### Acceptance criteria

- `challenge_1` family 1 yields three phases: `S1=9`, `S2=10`, final.
- Phase 1 contains `I2→M1 top`, `I1→M1 bottom`, `M1→P1 top`, `M1→P1 bottom`,
  `P1→S2` — and does **not** contain `I1→P1 top` or `I2→P1 bottom`, which are
  live at that moment but feed nothing the latch depends on.
- The final phase contains seven wires, including ones placed before the last
  latch.
- Evaluating each phase's wires yields its terminator value at the latch
  producer; evaluating the final phase gives every output its target.
- A solution containing a latch never read afterwards emits no phase for it.

### Cross-check

Independently replaying the rendered transcript per §19.8 must produce identical
phases. Keep that replay as a test oracle even though it is not the production
path — two derivations agreeing is the strongest available correctness signal,
given no Godot in the loop.

---

## CR-P2 — Canonical intra-phase ordering

**New file:** `tools/level_generator/emitter/ordering.py`
**Depends on:** CR-P1

### Behaviour

Order each phase's wires by topological walk over its target nodes: a node is
emitted only after every node feeding it; on reaching a node, emit all of its
input wires contiguously in ascending port order.

Ties among simultaneously-ready nodes break by `operations`-array order, then
`outputs`-array order.

Ordering does not affect hint-system correctness — a phase is evaluated as a
set. It affects the player directly, because hints are offered in list order.
Two properties must hold, and are the reason this is its own module rather than
an incidental sort:

1. A node's input wires precede any wire leaving that node.
2. A multi-input node's input wires are contiguous. Written per-node, not as
   "two steps," so it survives node types with more than two inputs.

The phase's wiring is always a DAG — `GraphCanvas` blocks cycles — so a
topological order always exists. Fail loudly rather than falling back to
insertion order if one cannot be produced.

### Acceptance criteria

- `challenge_1` phase 1 orders as `I2→M1 top`, `I1→M1 bottom`, `M1→P1 top`,
  `M1→P1 bottom`, `P1→S2`.
- `challenge_1` final phase orders as `S1→P1 top`, `S2→P1 bottom`, `S2→M1 top`,
  `S1→M1 bottom`, `M1→O1`, `S2→O2`, `P1→O3`.
- The latch connection is last in every non-final phase without special-casing —
  it is a sink, so topological order places it there. Assert it regardless.
- Output-targeted wires are last in the final phase.
- Ordering is deterministic: two runs over the same input produce byte-identical
  sequences.

---

## CR-P3 — Structural validation

**New file:** `tools/level_generator/emitter/validate.py`
**Depends on:** CR-P1, CR-P2

### Behaviour

Implement every check in §19.13 as an assertion over the intermediate
representation, run before serialisation. A failure aborts emission; it never
warns and continues.

1. **Arithmetic, per phase.** Non-final phases: evaluating the wiring gives the
   terminator's value at the latch producer. Final phase: every output receives
   its declared target, no node partially wired.
2. **Latch placement.** Last connection of each non-final phase targets the
   store its terminator names; no other connection in that phase targets it.
3. **No empty phase.** Every terminator preceded by at least one connection in
   its own phase.
4. **No dead latch.** Every terminator's store is read in some later phase or in
   the final phase.
5. **Distinct required states.** Compute each phase's required store state — per
   store, the value of the last terminator on it, retained only if some phase
   from that point on reads the store before re-latching it — and assert no two
   phases in a path produce identical maps. A collision makes the hint system
   silently skip a phase's work.
6. **Topological ordering.** As CR-P2, re-checked independently of the code that
   produced it.
7. **Referential integrity.** Every `(type, slot)` referenced exists in the
   emitted arrays.
8. **Engine limits.** Against `LevelBuilder`'s `INPUT_MAX` / `OPERATION_MAX` /
   `OUTPUT_MAX`, parsed from `level_builder.gd` rather than hardcoded. These
   have changed before.
9. **Display ranges.** Every emitted value within its §9 range.

Check 5's required-state computation is the same analysis the game performs at
runtime (`HINT_SYSTEM_PHASE_CHANGE_REQUESTS.md` CR-1). Implement it from that
specification, not by porting the GDScript — two independent implementations
agreeing is the point.

### Acceptance criteria

- A correctly emitted `challenge_1` passes all nine.
- Hand-corrupting each invariant in turn produces a distinct, actionable failure
  naming the level, path, and phase.

---

## CR-P4 — `.tres` serialisation

**New file:** `tools/level_generator/emitter/tres.py`
**Depends on:** CR-P1, CR-P2

### Behaviour

Serialise the validated intermediate representation to Godot resource text per
§19.11 and §19.2. Specifically:

- Script paths and UIDs read from the `.uid` files in the project at run time,
  never hardcoded. The instructions document carried a wrong filename for an
  extended period precisely because it was a static copy.
- Node type ordinals read from `node_type_registry.gd` at run time, same reason.
- Slot numbering per §19.5: 0-based index among nodes of the same `NodeType`, in
  emitted array order.
- `from_value` / `to_value` per §19.7 — set for INPUT, OUTPUT, ADD_VALUE only;
  for ADD_VALUE the node's *offset*, never the flowing value printed in the
  transcript.
- Omit every property at its default.
- Sub-resource blocks before any reference to them; readable ids.
- No `uid=` in the header; no comment lines in emitted output.

### Acceptance criteria

- Emitting `challenge_1` produces a file matching §19.12's worked example
  modulo sub-resource id naming.
- Re-parsing an emitted file reconstructs the same phases, wire sets, and
  terminators it was built from.
- Changing a script's UID in the project changes the emitted output on the next
  run with no code edit.

---

## CR-P5 — End-to-end CLI

**New file:** `tools/level_generator/emit.py`
**Depends on:** CR-P1 … CR-P4

### Behaviour

One command from approved level JSON to a `.tres` in
`math-machine/Levels/LevelData/<Category>/`:

```
python3 emit.py levels/Challenge/challenge_4.json --category Challenge
```

Stages: solve via `api.py` → collapse families to distinct final configurations
per §19.10, keeping the shortest journey per class → extract phases → order →
validate → serialise → write.

Emit a report matching §19.14: file path, family count → distinct path count,
phase count and latch sequence per path, and the bound/latch limit the solve
used.

Refuse to overwrite an existing file without `--force`.

### `LevelManager` registration

`LevelManager` holds `@export var level_data_list: Array[LevelData]`, stored in
`Singletons/LevelManager/level_manager.tscn`. Getting a level playable requires
adding the resource there.

**Do not edit that `.tscn` automatically.** Print the exact `ExtResource` line
and array entry for the designer to paste, and state where. Programmatic
`.tscn` editing is the one step here with a real corruption risk and no
validation available short of opening the editor; the manual paste is seconds of
work against that.

Revisit if it becomes a bottleneck at volume.

### Acceptance criteria

- Emitting all ten store-bearing levels succeeds with no manual intervention.
- Emitting a level that fails any CR-P3 check exits non-zero, writes nothing,
  and names the failure.
- The printed registration snippet is directly pasteable.

---

## CR-P6 — Test corpus

**New file:** `tools/level_generator/emitter/test_emitter.py`
**Depends on:** CR-P1 … CR-P5

### Behaviour

- **Golden files** for all ten store-bearing levels plus two store-free levels.
  Regenerating must be byte-identical; a diff is a deliberate decision, not a
  surprise.
- **Dual-derivation cross-check** (CR-P1): structured extraction versus
  transcript replay, asserted equal on every corpus level.
- **Round-trip**: emit → re-parse → compare against the intermediate
  representation.
- **Invariant corruption**: each CR-P3 check has a test that breaks exactly that
  invariant and asserts the specific failure.
- **Store-free regression**: `AddValue` and `SumAndSubtract` levels emit a
  single-phase path with an empty required state, and their connection sets
  match what currently ships.

That last one is the real safety net for the migration: those levels' behaviour
must not change at all.

---

## CR-P7 — Headless Godot import check

**New file:** `tools/level_generator/check_import.sh` (or equivalent)
**Depends on:** CR-P5
**Priority:** lower than CR-P1–P6; do last

### Behaviour

The instructions document currently ends with *"You cannot run Godot, so import
is unverified. Ask the designer to open the project once."* That is the last
unautomated correctness gap in the pipeline.

Add a check that runs the Godot binary headlessly against the project to confirm
emitted resources import without errors, and — better — runs the CR-6 validation
from the game side over every `LevelData` in `level_data_list`, exercising the
same code the game uses rather than a Python reimplementation.

Godot 4 supports headless operation and script execution from the command line;
**confirm the exact invocation against the 4.7 documentation before relying on
it** rather than assuming flags carried forward. Exit non-zero on any
`push_error` output.

### Acceptance criteria

- A well-formed emitted resource passes.
- A resource referencing a nonexistent script path fails, catching the class of
  error the wrong `StoreValueStepData.gd` filename would have caused.
- Runs in CI or as a single command, with the Godot binary path configurable.

---

## CR-P8 — Node array ordering

**New file:** `tools/level_generator/emitter/layout.py`
**Depends on:** nothing; consumed by CR-P4

### Behaviour

Order the three `GraphNodeData` arrays before the `(type, slot)` map is built.
Full specification in `LEVEL_GENERATION_AGENT_INSTRUCTIONS.md` §19.4 and §19.4a;
this CR implements it.

- **Inputs and outputs**: ascending by value. Both are guaranteed distinct by §3,
  so this is a total order.
- **Operations**: the grid layout algorithm in §19.4a — group non-store types,
  sort groups by count descending then LARGE-before-SMALL then ordinal, claim
  slot shapes from the table, then fill remaining slots with singles by ordinal
  and stores last.

The size-group table (LARGE: Sum, Subtract; SMALL: Add Value, Store) must be a
single declaration extended by adding a line, since the unimplemented node types
in `NodeTypeRegistry` will need entries. A type in neither group is an authoring
error — raise, do not default.

### Sequencing hazard

`LevelBuilder` places operation *i* at location slot *i*, and every `slot` field
in the solution data derives from array position. **Ordering must complete before
the `(type, slot)` map is built.** Ordering afterwards produces a file that loads
cleanly and points every hint at the wrong node — the worst possible failure
mode, since nothing detects it short of playing the level.

Make this structural: have the ordering function return the arrays and the map
together, so there is no way to obtain a map from an unordered array.

### Acceptance criteria

Every row of §19.4a's worked-cases table, plus:

- The fallback path fires for n=6 with 3+2: the triple takes `{0,2,4}`, all of
  the pair's listed shapes are blocked, and it lands on `{1,3}`.
- n=4 with 3-of-a-type takes the no-shape path and falls through to step 4
  rather than claiming.
- Ordering is deterministic and stable — same input, byte-identical output.
- A `NodeType` absent from both size groups raises rather than silently sorting
  by ordinal alone.
- Slot numbers in emitted solution steps match the post-ordering array
  positions. Round-trip test: re-parse the emitted `.tres`, rebuild the map from
  its own arrays, and confirm every step still resolves to the intended node.

### Note on existing levels

This reorders the arrays of every level, including store-free ones untouched by
the hint-system work. Their `.tres` files will change even where the solution
data does not. Regenerate all of them, not just the ten in CR-7 of
`HINT_SYSTEM_PHASE_CHANGE_REQUESTS.md`, and expect the CR-P6 golden files for
`AddValue` and `SumAndSubtract` to change on this CR — that is the one place
where a golden diff is expected rather than a red flag.

---

## Ordering

```
CR-P1 ─── CR-P2 ─┬─ CR-P3 ─┐
        CR-P8 ───┼─ CR-P4 ─┴─ CR-P5 ─── CR-P6 ─── CR-P7
```

CR-P8 is independent of the phase work and can be built first or last.

CR-P1 and CR-P2 are the substance. CR-P3 and CR-P4 are independent of each other
and can be parallelised. CR-P7 is separable and can be deferred indefinitely
without weakening the rest.

## Out of scope

- `generate.py` and everything under `level_verifier/` except importing
  `api.py`.
- Level selection, tier assignment, curation — the curating agent's judgment.
- Game code. See `HINT_SYSTEM_PHASE_CHANGE_REQUESTS.md`.
- Automated `.tscn` editing, including `LevelManager` registration.

## Consequence for the agent instructions

Once CR-P5 lands, §19.3 through §19.13 stop being a procedure an agent executes
and become the emitter's specification. §19 should shrink to: the approval gate,
how to invoke `emit.py`, how to read its report, and the manual registration
step. That edit is deliberately not part of this document — make it after the
tool exists and its behaviour is settled, so the instructions describe something
real rather than something planned.
