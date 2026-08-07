# Hint System — Phased Solution Paths

Change requests for reworking the hint system so store-node levels receive
connection-level hints throughout, not just after every store holds its final
value.

Each change request is scoped for the implementation agent. Per pipeline
convention the testing agent writes tests from these descriptions *before*
implementation, so behaviour here is stated in full rather than by reference to
existing code.

---

## 0. Model summary

### The problem being fixed

Every value in the graph is a pure function of the current wiring, with one
exception: `StoreNode` latches its input and auto-severs, so a store's value is
*history*, not a function of the current layout.

The current data model handles this by treating store values as preconditions
(`StoreValueStepData`, listed first) and connections as the single final layout.
While any store is still unsatisfied, the only hint available is a ghost number
on the store — no guidance on how to reach it.

The blocking consequence for any count-based fix: `node.value == step.value` can
only ever detect the **most recent** latch on a store. "S1 held 3 at some point"
is unobservable from current state, so a path where S1 goes 3 → 12 cannot be
tracked by counting satisfied store steps.

### The new model

A `SolutionPath` becomes an ordered sequence of **phases**. Each phase is a set
of connections terminating in one store latch; the last phase terminates in
level completion instead.

Within a phase, ordering does not matter — only the wiring at the instant of the
latch has any effect, so a wire made and replaced inside the same phase was
wasted motion. Each phase is therefore describable declaratively as a set of
`ConnectionStepData`, exactly as the final layout is today.

Progress is tracked by a **phase cursor** derived from a per-phase **required
store state**, computed by liveness analysis over the path. No runtime latch
history is recorded; the cursor is a pure function of current store values,
which makes it restart-safe and impossible to desynchronise.

### Encoding decisions (locked)

| Decision | Choice |
|---|---|
| Resource shape | Flat `solution_steps` array; `StoreValueStepData` acts as a phase **terminator** |
| Terminator position | **End** of its phase — inverts today's convention |
| Phase step lists | **Snapshots** (every wire that must be live at the latch), not deltas |
| Journeys per family | One canonical journey per solution family |
| Store ghost value | Retained, as a secondary cue on the latch connection hint |

### Glossary

- **Phase** — a maximal run of `CONNECTION` steps, plus the `STORE_VALUE`
  terminator that closes it. The trailing run with no terminator is the **final
  phase**.
- **Terminator** — the `StoreValueStepData` step ending a phase. Records which
  store slot latches and to what value. Structural, never shown as a hint.
- **Latch connection** — the last `CONNECTION` step of a non-final phase; its
  `to_type` is `STORE`. Making this wire causes the latch.
- **`required_state(k)`** — map of store slot → value that must currently hold
  for phase `k` to be the player's position.
- **Cursor** — the highest phase index whose `required_state` currently holds.

### Worked reference: `challenge_4.tres` path 0

Current authored form is `[sv S2=1] [sv S1=12] [7 connections]`. Phased form:

```
phase 0  c: I1→P1 top      c: I1→P1 bottom   c: I2→M1 top
         c: P1→M1 bottom   c: M1→S1          sv: S1=3
phase 1  c: S1→M1 top      c: I1→M1 bottom   c: M1→S2          sv: S2=1
phase 2  c: I2→P1 top      c: I2→P1 bottom   c: P1→M1 top
         c: M1→S1          sv: S1=12
phase 3  c: S1→P1 bottom   c: S2→O1          c: M1→O2          c: P1→O3
```

Derived required states:

| Phase | latches | reads stores | `required_state` | why |
|---|---|---|---|---|
| 0 | S1=3 | — | `{}` | nothing latched yet |
| 1 | S2=1 | S1 | `{S1:3}` | phase 1 reads S1 |
| 2 | S1=12 | — | `{S2:1}` | S1's 3 is dead — phase 2 re-latches S1; S2's 1 is read in phase 3 |
| 3 | — | S1, S2 | `{S1:12, S2:1}` | both read by outputs |

Resulting cursor behaviour (this table is the primary acceptance fixture for
CR-1 and CR-4):

| S1 | S2 | phases matching | cursor |
|---|---|---|---|
| unset | unset | 0 | 0 |
| 3 | unset | 0, 1 | 1 |
| 3 | 1 | 0, 1, 2 | 2 |
| 10 | 1 | 0, 2 | 2 |
| 12 | 1 | 0, 2, 3 | 3 |
| 99 | unset | 0 | 0 |
| 3 | 5 | 0, 1 | 1 |

Note row 4: cursor is 2 even though S1 holds a value the path never asks for,
because phase 2 neither reads S1 nor depends on it. Note row 6: a destructive
latch rolls the cursor back to 0 with no special-casing.

---

## CR-1 — Phase decomposition and required-state analysis on `SolutionPath`

**Files:** `math-machine/HintSystem/solution_path.gd`
**Mode:** propose-first (new architecture)
**Depends on:** nothing

### Behaviour

Add phase decomposition and liveness analysis to `SolutionPath`. This CR is
purely additive — no existing caller changes behaviour yet.

**Phase decomposition.** Split `solution_steps` into phases at each
`STORE_VALUE` step, with the terminator belonging to the phase it closes. A
trailing run of `CONNECTION` steps with no terminator forms the final phase. A
path with no `STORE_VALUE` steps has exactly one phase.

Expose, at minimum:

- the phase count
- the `CONNECTION` steps of a given phase, in authored order
- the terminator of a given phase, or `null` for the final phase
- the latch connection of a given phase (last `CONNECTION` step), or `null` for
  the final phase

**Required state.** For phase index `k`, `required_state(k)` maps store slot →
required value. For each store slot `s`:

1. `last_latch(s, k)` = the value of the last terminator on slot `s` among
   phases `< k`. If there is none, `s` contributes nothing.
2. `s` is **live at `k`** iff, scanning phases `j = k, k+1, … , n` in order:
   - if phase `j` contains a `CONNECTION` step with `from_type == STORE` and
     `from_slot == s`, `s` is live — stop.
   - otherwise, if phase `j`'s terminator has `slot == s`, `s` is dead — stop.
   - otherwise continue to `j + 1`. Falling off the end means dead.
3. `s` appears in `required_state(k)` with value `last_latch(s, k)` iff it has a
   last latch and is live at `k`.

The read check must precede the re-latch check **within the same phase**, since
a phase may both read a store and re-latch it (phase 1 above reads S1 into M1
and latches S2; phase 2 re-latches S1 without reading it).

`required_state(0)` is always empty.

Results are a pure function of `solution_steps` — cache them on first use.

### Acceptance criteria

- On a path with no `STORE_VALUE` steps: one phase, containing every step;
  `required_state(0)` empty.
- On `challenge_4` path 0 as phased in §0: four phases, with the required states
  in the table above.
- Phase 2's required state excludes S1 (dead — re-latched in the same phase) and
  includes S2 (live — read in phase 3).
- Phase 1's required state includes S1, established by phase 0's terminator and
  read within phase 1 itself.
- A store latched in some phase and never subsequently read appears in no
  required state.

---

## CR-2 — Phase-scoped satisfaction context on `SolutionStep`

**Files:** `math-machine/HintSystem/solution_step.gd`
**Mode:** propose-first (signature change with call-site impact)
**Depends on:** CR-1

### Behaviour

`SolutionStep.is_satisfied` currently takes the whole `SolutionPath`, used only
by `_required_connection_count` to disambiguate multiple steps sharing a
from-node/to-node pair on a commutative target. Under phasing, that
disambiguation must be scoped to a **single phase**, not the whole path — the
same wire legitimately recurs across phases and cross-phase counting would
inflate the required connection count and leave steps permanently unsatisfied.

Change the satisfaction context from "the path" to "the connection steps of one
phase." `_required_connection_count` then computes this step's 1-based ordinal
among the steps *of that phase* sharing the same resolved `from_node`,
`from_port`, and `to_node`.

`STORE_VALUE` steps are never evaluated for satisfaction under the new model;
if `is_satisfied` is called on one it should return `false` rather than
comparing values, so a stray terminator cannot be mistaken for progress.

### Notes for the implementation and testing agents

**The latch connection of a phase is never satisfiable.** `StoreNode.update_input`
calls `_disconnect_input()` immediately on latching, so the wire that caused the
latch no longer exists the instant it takes effect. This is correct and
intended: once the latch succeeds the cursor advances past that phase, so the
step is never consulted again. Any test asserting that a completed latch
connection reads as satisfied is asserting the wrong thing.

### Acceptance criteria

- Two steps in the same phase both requesting `S1 → P1` (commutative target) are
  satisfied only when two live wires exist, as today.
- A step requesting `I2 → P1 top` in phase 2 is unaffected by a step requesting
  `I1 → P1 top` in phase 0 — different from-nodes, no interaction.
- Two steps in *different* phases both requesting `I2 → P1` are each satisfied by
  one live wire; neither requires a second.
- `is_satisfied` on a `STORE_VALUE` step returns `false`.

---

## CR-3 — Joint binding × cursor evaluation on `SolutionPath`

**Files:** `math-machine/HintSystem/solution_path.gd`
**Mode:** propose-first
**Depends on:** CR-1, CR-2

### Behaviour

The cursor depends on which live nodes are bound to which slots, and binding
quality depends on the cursor. Resolve this by maximising over both together.

Replace `resolve_bindings()` with an evaluation returning bindings, the phase
cursor, and the score. Suggested carrier: a small `RefCounted` (`PathEvaluation`)
with `bindings: Dictionary`, `phase_index: int`, `score: Vector3i` — statically
typed, per project convention.

For every candidate full binding produced by the existing permutation and
cartesian-product machinery:

1. `cursor` = the **highest** phase index `k` such that every `(slot, value)` in
   `required_state(k)` is matched by a bound, live store node holding that
   value. Phase 0 always matches, so a cursor always exists.
2. `score` = `Vector3i(cursor, satisfied connections in phase cursor,
   -(unsatisfied connection steps from phase cursor to the end))`.
3. Compare lexicographically, strictly, so ties fall through to the earliest
   candidate as today.

Return the best `(bindings, cursor, score)`.

**Remove the store-slot value pruning path.** `_candidates_for_type` currently
prunes candidates by `_slot_value_requirements`, which only ever applies to
`fixed_value_types` (Input, Output, Add Value) and so never covered Store. Do
not extend it to Store — a store slot has no single required value across a
path, its required value is per-phase. The joint maximisation subsumes this: a
binding that places the wrong physical store in a slot scores a lower cursor and
loses. Existing pruning for Input/Output/Add Value stays as-is.

### Design note

The cursor is `max k`, not "longest matching prefix" — `required_state` is
deliberately non-monotone (see phase 2 above). This is sound because store state
is the only hidden state in the game: if the required stores hold the required
values, the phase is genuinely reachable regardless of the route taken. CR-6
adds the authoring invariant that keeps `max k` from silently skipping work.

### Acceptance criteria

- On a level with two stores, a board where the physical store holding the
  required value is not the one in scene-child order still resolves to the
  binding that yields the higher cursor.
- On a no-store level, evaluation returns cursor 0 and the score's second
  component equals the count of satisfied connections, reproducing today's
  ranking behaviour.
- The `challenge_4` cursor table in §0 reproduces through evaluation, for each
  listed pair of store values.

---

## CR-4 — Cursor-based path ranking and hint selection

**Files:** `math-machine/HintSystem/level_solution_data.gd`
**Mode:** propose-first
**Depends on:** CR-3

### Behaviour

**`get_current_path`.** Delete the two-tier scheme (all-stores-satisfied →
most connections; else most satisfied stores). Evaluate every path via CR-3 and
pick the highest `score`, comparing lexicographically. Ties go to the earliest
path in `solution_paths`, as today. Empty `solution_paths` returns `null`;
otherwise a path is always returned, so the `solution_paths[0]` fallback is no
longer reachable and should go.

Cache the winning path, its bindings, **and its cursor** — `get_hint_target` and
the port-reservation logic all need the phase.

**`get_next_hint`.** Return the first unsatisfied `CONNECTION` step in the
**cursor phase only**, or `null` if every connection in that phase is satisfied.
Never return a `STORE_VALUE` step. Do not search phases before or after the
cursor.

Because the latch connection is authored last in its phase (CR-6 enforces this),
first-unsatisfied-in-order naturally withholds it until the rest of the phase is
wired — which is what prevents the player from wiring `M1 → S1` early and
latching garbage.

**`_reserved_ports`.** Scope the scan to the cursor phase's connection steps
rather than the whole path. A reservation established by a step three phases ago
does not constrain the current phase and would misdirect the hint on a
commutative target.

**`get_hint_target`.** Drop the `STORE_VALUE` branch — it is now unreachable.
For `CONNECTION` steps, behaviour is unchanged, except that when `to_type` is
`STORE` the returned dictionary must also carry the value that the phase's
terminator records, so the presentation layer can show it (CR-5). Suggested key:
`"store_value"`, absent for non-latch steps.

### Acceptance criteria

- On a store level with the player mid-phase, the hint is a connection, never a
  ghost value alone.
- With every connection in the cursor phase satisfied except the latch
  connection, the hint is the latch connection, carrying the terminator's value.
- With the cursor at the final phase and every connection satisfied,
  `get_next_hint` returns `null`.
- Between two paths whose cursors differ, the higher-cursor path wins regardless
  of connection counts.
- Between two paths at equal cursor, the one with more satisfied connections in
  its cursor phase wins; at equal cursor and equal satisfied count, the one with
  fewer remaining unsatisfied steps wins.
- On every existing no-store level, hint sequences are unchanged from current
  behaviour.

---

## CR-5 — Hint presentation for latch connections

**Files:** `math-machine/Levels/level.gd`
**Mode:** propose-first (touches presentation contract)
**Depends on:** CR-4

### Behaviour

In `_on_hint_button_pressed`, remove the `SolutionStep.Type.STORE_VALUE` match
arm — the hint system no longer emits those steps.

For a `CONNECTION` hint, call `graph_canvas.set_hint_connection` as today.
Additionally, when the target dictionary carries a store value (i.e. the hinted
wire is a latch connection), call `show_hint_value` on the destination
`StoreNode` with that value, so the player sees both the wire to make and the
number it will capture.

`StoreNode.show_hint_value` and `HintVisuals` are unchanged.

> CR-9 generalises the condition under which the ghost value appears. If both are
> being implemented together, read CR-9 first — this CR's latch-only rule becomes
> the disabled-flag fallback there.

### Acceptance criteria

- Hinting a non-latch connection glows the wire and shows no ghost value.
- Hinting a latch connection glows the wire *and* pulses the target value on the
  destination store.
- `graph_canvas.clear_hint_connection()` on a null hint still clears, as today.
- Making or breaking any connection clears the hint, as today.

---

## CR-6 — Authoring validation for phased paths

**Files:** `math-machine/HintSystem/` (new validation entry point; placement at
implementer's discretion)
**Mode:** propose-first
**Depends on:** CR-1

### Behaviour

The flat-list encoding makes phase structure a convention rather than a type, so
the invariants it rests on need checking explicitly. Provide a validation
routine over a `LevelSolutionData` reporting via `push_error`, callable from a
test or an editor tool. It must flag:

1. **Latch connection not last.** In every non-final phase, the last
   `CONNECTION` step must have `to_type == STORE` and its `to_slot` must equal
   the phase terminator's `slot`. Anything else means the hint order will invite
   a premature latch.
2. **Duplicate required states.** No two phases within one path may have
   identical `required_state`. If they do, `max k` silently skips the earlier
   phase's work. Under canonical authoring this cannot occur, because a phase's
   latch appears in the following phase's required state whenever it is ever
   read — so a violation indicates a dead latch or a mis-ordered path.
3. **Dead latches.** Every terminator's slot must be read by some later phase,
   or be part of the final phase's required state. A latch nothing ever reads is
   wasted authoring and should not have been emitted.
4. **Empty phases.** No phase may consist of a terminator with no connection
   steps.
5. **Referential integrity**, as today: every `(type, slot)` referenced by any
   step must be satisfiable by the level's node arrays.

### Acceptance criteria

- A correctly phased `challenge_4` path 0 passes all five checks.
- Moving the latch connection off the end of a phase fails check 1.
- Appending a terminator that duplicates an earlier phase's required state fails
  check 2.
- A path whose second store is latched but never read fails check 3.

---

## CR-7 — Regenerate level resources

**Files:** `math-machine/Levels/LevelData/Store/store_1..5.tres`,
`math-machine/Levels/LevelData/Challenge/challenge_1..5.tres`
**Mode:** propose-first (bulk data)
**Depends on:** CR-6

Re-emit every level whose solution data contains `StoreValueStepData` into the
phased format. Ten files: five Store, five Challenge. Levels in `AddValue/` and
`SumAndSubtract/` have no stores — a single-phase path with an empty required
state — and should be left untouched.

This is level-generation work, not game-code work. The authoring procedure —
transcript replay, per-phase snapshotting, step ordering, and the `.tres`
format — is already specified in
`tools/level_generator/LEVEL_GENERATION_AGENT_INSTRUCTIONS.md` §19, which has
been updated for the phased format. Follow that document; do not re-derive the
procedure from this one.

Expect roughly 2.5–3× growth in connection step count on store levels
(`challenge_1`'s nine paths go from about seven connection steps each to
roughly eighteen). These files become impractical to hand-edit; treat them as
generated artifacts from here.

### Acceptance criteria

- Every regenerated file passes all CR-6 checks.
- Every path's final phase reproduces that path's current authored connection
  set, so end-of-level behaviour is unchanged.
- Path counts per level are unchanged (one canonical journey per family).

---

## CR-8 — Multi-input hints as a group

**Files:** `math-machine/HintSystem/level_solution_data.gd`,
`math-machine/Graph/Graph Canvas/graph_canvas.gd`,
`math-machine/Levels/level.gd`
**Mode:** propose-first (multi-file, changes the hint presentation contract)
**Depends on:** CR-4, CR-5

### Rationale

A hint for one input of a two-input node is misleading on its own. The player
wires it, the node still outputs the wrong value because the other input is
wrong or missing, and the hint appears to have been bad advice. Showing every
missing input at once tells the player what the node should be producing, not
just one wire it needs.

### Behaviour

**Grouping.** When `get_next_hint` yields a `CONNECTION` step, extend it to the
**run of consecutive steps in the cursor phase sharing the same resolved `to`
node**, then hint every step in that run that is not yet satisfied.

Scan forward from the returned step while the next step's resolved `to` node is
the same node; stop at the first step with a different `to` node or at the end
of the phase. Steps within the run that are already satisfied are **skipped for
display but do not stop the scan** — a satisfied step in the middle of a run
must not truncate it.

Generalise to any run length. Do not special-case two.

Scanning forward only is sufficient. A step earlier in the run than the returned
one is necessarily satisfied — `get_next_hint` returns the *first* unsatisfied
step — and satisfied steps are never displayed, so nothing is lost.

Worked, for a three-input node with steps 1–3 in one run and step 2 already
satisfied: `get_next_hint` returns step 1; the scan collects steps 1, 2, 3;
display shows steps 1 and 3.

**Why the run is well defined.** §19.9 of the level generation instructions
requires a node's input connections to be contiguous within a phase, and §19.13
check 3e enforces it. Two consecutive steps targeting the same node otherwise
have no meaning — the second would immediately auto-sever the first. This CR
depends on that invariant; if it is ever relaxed, this grouping breaks silently.

**Port assignment across the group.** For a non-commutative target
(Subtract), each step's declared `to_port` is distinct and used as-is.

For a commutative target (Sum), ports must be assigned across the whole group at
once so that no two hint wires point at the same port. The existing
`_hint_to_port` resolves one step against ports already claimed by *satisfied*
steps; it has no knowledge of a second pending hint. Extend it, or wrap it, so
that a port assigned to one member of the group is unavailable to the others.
This is the main implementation risk in this CR.

**Rendering.** `GraphCanvas` currently holds a single `_hint_connection`.
Replace with a collection, drawn in the same style. Keep one shared alpha and
one tween so the group pulses in sync rather than drifting out of phase.
`clear_hint_connection` clears all of them; making or breaking any connection
still clears, as today.

Prefer a plural entry point (`set_hint_connections`) over repeated calls to the
singular one, so a group replaces the previous group atomically.

**A group is never a latch connection.** Store has one input port, so a run
containing the latch connection always has length one, and CR-5's ghost-value
behaviour is unaffected.

### Acceptance criteria

- A Subtract node with neither input wired hints both connections at once, to
  ports 0 and 1 respectively.
- With one input already correctly wired, only the missing one is hinted.
- A run of three steps into one node with the middle step satisfied hints the
  first and third.
- A Sum node fed twice from the *same* source node, with neither wire made,
  hints two wires to two distinct ports.
- The same case with one wire already live hints exactly one wire, pointing at
  the free port — `_required_connection_count` already makes `get_next_hint`
  return the second step here, so the group is correctly a single step.
- A single-input target (Add Value, Store, Output) hints exactly one connection,
  identically to CR-5 behaviour.
- All hint wires in a group pulse in sync.
- Making any one connection in a hinted group clears the whole group; pressing
  hint again re-hints the remainder.

---

## CR-9 — Phase goal value on every hint

**Files:** `math-machine/HintSystem/hint_visuals.gd`,
`math-machine/HintSystem/level_solution_data.gd`,
`math-machine/Levels/level.gd`
**Mode:** propose-first (multi-file, behind a flag)
**Depends on:** CR-4, CR-5

### Rationale

A hint currently answers "what wire next?" but not "what for?". Inside a latch
phase, every connection exists to put one specific number into one specific
store — and the player has no way to see that until the final wire of the phase.

Showing the phase's goal value throughout gives the player the target to reason
toward, which is the thing most likely to get them experimenting again rather
than pressing hint repeatedly.

### Behaviour

While the cursor is on a **non-final phase**, every hint pulses that phase's
terminator value on the store the terminator names — regardless of which
connection is being hinted.

The store showing the ghost is usually **not** the node the hinted wire points
at. Hinting `I2 → M1 top` in a phase that latches `S2 = 10` glows that wire and
pulses `10` on `S2`, elsewhere on the board. That separation is the feature: it
reads as "this wiring is building toward 10 in that store."

Specifics:

- **Final phase**: no ghost value. There is no terminator and no goal store.
- **One ghost per hint**, not one per connection. When CR-8 shows a group of
  wires into a multi-input node, the single phase-goal ghost still applies.
- **Existing pulse behaviour is unchanged** — `HintVisuals.STORE_VALUE_PULSE_COUNT`
  beats, then revert to the store's real state via `_update_value_label`.
  `StoreNode` needs no changes.
- `get_hint_target` returns the phase's goal store node and value for **any**
  step in a non-final phase, not only for the latch connection. This supersedes
  CR-5's narrower rule.

### The flag

Add a single constant to `HintVisuals`:

```gdscript
## When true, every hint inside a latch phase pulses that phase's goal value on
## its store, not just the hint for the wire that causes the latch.
## Set false to fall back to latch-connection-only (see CR-5).
const SHOW_PHASE_GOAL_VALUE: bool = true
```

`HintVisuals` is the right home — it already owns the shared visual language for
hints, and putting the flag there keeps the decision next to the constants that
govern how the ghost looks.

**Read it in exactly one place**, the branch in `level.gd` that decides whether
to call `show_hint_value`. Do not consult it inside `LevelSolutionData` — let
`get_hint_target` always return the goal store, and let the presentation layer
decide whether to use it. That keeps the hint system's data contract stable
whichever way the flag goes, and confines the experiment to one `if`.

**With the flag false, behaviour must be exactly CR-5** — ghost on latch
connections only. Turning the experiment off must not also remove the ghost from
the latch hint, which is established behaviour and not part of this experiment.

**To remove the feature entirely**: delete the constant, delete the branch in
`level.gd`, and narrow `get_hint_target` back to returning store fields only when
`to_type` is `STORE`. Three edits, no other code depends on it.

If it proves worth keeping, promoting the flag to a player-facing setting is
also a small change, since the read is already funnelled through one call site.

### Acceptance criteria

- Hinting any connection in a non-final phase pulses that phase's terminator
  value on the store the terminator names.
- The ghost appears on the goal store even when the hinted wire targets a
  different node entirely.
- Hinting in the final phase shows no ghost value.
- A CR-8 group of several wires produces exactly one ghost.
- With `SHOW_PHASE_GOAL_VALUE = false`, ghosts appear on latch connections only,
  matching CR-5 exactly.
- The ghost always reverts to the store's true value when the pulse ends,
  including when the store currently holds a different number.
- Pressing hint repeatedly restarts the pulse rather than stacking tweens.

---

## Ordering and dependencies

```
CR-1 ─┬─ CR-2 ─── CR-3 ─── CR-4 ─┬─ CR-5 ─┬─ CR-8
      └─ CR-6 ─── CR-7           └────────┴─ CR-9
```

CR-1 through CR-5 are the game-side chain and must land in order. CR-6 can
proceed in parallel with CR-2 onwards; CR-7 needs CR-6. CR-8 and CR-9 are
independent presentation changes on top of CR-5; either can be deferred or
dropped without affecting anything else.

**The game will not play correctly between CR-4 and CR-7.** CR-4 expects phased
data; the shipped `.tres` files are not phased until CR-7. Under the old data
every path decomposes into a single final phase whose `required_state` is empty
(no terminators precede it), so hints degrade to "first unsatisfied connection
in the final layout" — the store-latching phase gets no hints at all rather than
wrong ones. Tolerable as an intermediate state, but the two CRs should land
close together.

## Out of scope

- `StoreNode`, `NodeTypeRegistry` — no changes. `GraphCanvas` is touched by CR-8
  only, and only its hint-rendering members. `HintVisuals` gains one feature-flag
  constant in CR-9 and is otherwise unchanged.
- Generator and verifier internals (`generate.py`, `level_verifier/`) — untouched.
- The level generation agent's instructions — already updated for the phased
  format; CR-7 consumes them rather than changing them.
- Levels without store nodes — behaviour must be identical throughout.
- Any change to how challenge mode consumes `LevelSolutionData`. `SolutionPath`
  remains general-purpose; a path is fully accomplished when its cursor reaches
  the final phase and every connection in that phase is satisfied.
