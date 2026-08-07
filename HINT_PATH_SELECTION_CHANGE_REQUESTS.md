# Hint Path Selection — Change Requests

Change requests for controlling *which* solution path the hint system works
from: forcing one for testing, excluding ones already completed in challenge
mode, and letting a player choose the solution they want to be guided toward.

These are game-side changes. CR-S1 has an emitter-side half, noted where it
applies.

---

## 0. What picks the path today

`LevelSolutionData.get_current_path` evaluates every path and takes the highest
score:

```gdscript
var best_score: Vector3i = Vector3i(-1, -1, -1)
for path in solution_paths:
    var evaluation: PathEvaluation = path.evaluate(graph_canvas)
    if not _is_better_score(evaluation.score, best_score):
        continue
    ...
```

The score is `Vector3i(cursor, satisfied connections in the cursor phase,
-unsatisfied connections from the cursor to the end)`, compared
lexicographically. `_is_better_score` uses strict `>`, so a tie leaves the
earlier path in place — array order is the tiebreak.

**But array order is only the tiebreak, and on `store_5` the tie does not
survive to the point where it matters.** See CR-S0.

---

## CR-S0 — A longer path hijacks the player at the final phase

**Files:** `math-machine/HintSystem/level_solution_data.gd`
**Depends on:** nothing
**This is a bug, not a design gap. Fix it first.**

### Symptom

On `store_5`, clicking the hint button repeatedly and doing exactly what it says
walks the player onto a path they did not start on and makes them do more work.
Reordering `solution_paths` does not change it.

### Diagnosis

Reproduced with `tools/hint_sim/hint_sim.py`, which ports the runtime hint loop
(`evaluate`, `is_satisfied`, `get_next_hint_group`, and `GraphCanvas`/`StoreNode`
connect semantics) to Python and plays a level by following its own hints.

The player follows path 0 for twelve clicks and reaches `S0=-8, S1=-10`, with
`S0→M1 top` and `I1→M1 bottom` live. At that moment:

| path | phases | cursor | satisfied in cursor phase | −unsatisfied | score |
|---|---|---|---|---|---|
| 0 | 7 | **6 — its final phase** | 0 | −4 | `(6, 0, -4)` |
| 2 | 8 | 6 — two latches still to go | **1** | −5 | `(6, 1, -5)` |

Path 0's final phase wants `I1→M1 top, S0→M1 bottom` — the *opposite* ports to
what is live — so nothing in it is satisfied. Path 2's phase 6 wants
`S0→M1 top`, which is live, so one step is.

Both tie on cursor. **Component 2 outranks component 3**, so path 2 wins on that
single already-satisfied wire, despite needing more total work and two extra
latch phases. The player is pulled off a path they were four wires from
finishing.

Two things make this possible, and both are worth stating separately:

1. **`satisfied in cursor phase` outranks `remaining work`.** A path can win by
   accident of which wires happen to be live, while being objectively further
   from done.
2. **`cursor` is compared as a raw index across paths of different lengths.**
   Cursor 6 of 7 phases means "finished latching"; cursor 6 of 8 means "two
   latches left". They are not comparable, but they tie.

Reordering cannot help because path 2 wins on score, not on the tiebreak.

### Recommended fix — hysteresis, not a scoring change

Reordering the score components is the obvious fix and it does not work: it
trades one level for another.

| variant | `store_5` | `challenge_4` | total wires, 25 levels |
|---|---|---|---|
| current `(cursor, sat, -unsat)` | 19 | 16 | 240 |
| `(cursor, -unsat, sat)` | 17 | **20** | 242 |
| `(-phases_left, -unsat, sat)` | 17 | **20** | 242 |
| `(-unsat)` alone | 17 | **never completes** | — |
| **current + hysteresis** | **17** | **16** | **238** |

(Wires the player must make while following hints only; lower is better.)

Keep the scoring exactly as it is and add stickiness: **once a path has been
chosen, keep it unless a challenger is strictly better on
`(cursor, -unsatisfied)`** — that is, genuinely closer to finishing, not merely
holding one more incidentally-satisfied wire.

That fixes `store_5` with no regression anywhere in the corpus and is a
strictly smaller change than re-deriving the ranking.

### Cost of hysteresis, stated honestly

Path *selection* stops being a pure function of the board. `SolutionPath`'s
docstring currently promises the cursor "is a pure function of current store
values and cannot desynchronise" — that remains true of the **cursor**, but the
**chosen path** would now depend on which path was chosen last.

Consequences to handle:

- The incumbent is per-level runtime state and must be cleared on level start
  and restart. Same hazard as CR-S2's scope: `LevelSolutionData` is a cached
  `Resource` shared between `Level` instances.
- Save/restore does not need it. On a fresh load there is no incumbent and
  selection falls back to pure scoring, which is correct.
- It interacts with CR-S2: an explicit pin should override the incumbent, and
  setting a pin should clear it.

If that state is unacceptable, the stateless alternative is to make cursor
comparable across paths — rank on phases *remaining* rather than cursor index,
and put remaining work above satisfied-in-phase. That is the `(-phases_left,
-unsat, sat)` row above: it fixes `store_5` but costs `challenge_4` four extra
wires. Worth re-testing with the simulator if hysteresis is ruled out.

### Acceptance criteria

- `hint_sim.py` completes `store_5` in 17 wires without changing path after the
  first choice.
- No level in the corpus needs more wires than it does today.
- Clicking hints only, the player never switches to a path with strictly more
  remaining unsatisfied connections than the one they are on.
- The incumbent does not survive a level restart.
- A pinned path (CR-S2) overrides the incumbent.

### Note on testing paths

Once CR-S0 lands, array order still only breaks genuine ties, so it remains a
poor test harness — `store_5`'s two shortest paths are byte-identical for
phases 0–4, so whichever is first produces the same 15 hints. CR-S2's pin is
what makes a specific path testable.

---

## CR-S1 — Stable path identity

**Files:** `math-machine/HintSystem/solution_path.gd`, plus the emitter
**Depends on:** nothing
**Do this first.** Everything else that names a path depends on it.

### Behaviour

`SolutionPath` has no identity today. A path is "path 3" — its index in
`solution_paths`. That is not durable enough to save against.

The `.tres` files are **generated artifacts**, regenerated whenever the level
pipeline changes. In the course of a single week `store_4` went 2 → 1 → 2 paths
and `store_5` went 6 → 2 → 6, purely from tuning what counts as a distinct
family. Any progress recorded as "completed path 3" would have silently
re-pointed at a different solution each time.

This is the same failure `SaveManager` already fixed once. Its own docstring:

> Progress is keyed by level scene UID rather than by position in
> `LevelManager.level_scenes`, so inserting, removing or reordering levels can
> never remap completion flags onto the wrong levels.

Version 1 keyed by index, version 2 by UID, with a migration. Per-path
completion needs the same treatment *before* anything is written to disk, not
after.

Add:

```gdscript
@export var path_id: StringName
```

emitted by the pipeline, derived from the path's **canonical final
configuration** — the store values the final network reads, plus the final
wiring, minimised over permutations of interchangeable node slots. That is
exactly the key `collapse.py::_final_key` and
`notation.family_signature_with_symmetry` already compute; this CR hashes it to
a short stable string and writes it into the resource.

Canonicalising over slot permutations is not optional. The hint system performs
that permutation search at runtime, so two `.tres` files differing only in which
physical store is slot 0 describe the same solution and must produce the same
id.

### Acceptance criteria

- Regenerating a level's `.tres` with no change to the level JSON produces
  identical `path_id`s.
- Reordering `solution_paths`, or reordering the node arrays (§19.4a), does not
  change any `path_id`.
- Two paths within one level never share a `path_id`. If they do, §19.10's
  collapse should have merged them — fail emission rather than emit a
  collision.
- Adding a genuinely new solution to a level leaves the existing paths' ids
  untouched.
- `path_id` is stable across a store-slot relabelling of the same solution.

### Note

`path_id` identifies a solution *within* a level. It does not need to be
globally unique — `(level uid, path_id)` is the save key.

---

## CR-S2 — Hint scope: pin and allow

**Files:** `math-machine/HintSystem/level_solution_data.gd`
**Depends on:** CR-S1

### Behaviour

All three of the needs in this document are the same mechanism: constrain which
paths `get_current_path` may choose from, and optionally force one.

```gdscript
## Restrict path selection to these ids. Empty means "all paths".
func set_allowed_paths(ids: Array[StringName]) -> void

## Force hints to work from exactly this path, whatever it scores.
func pin_path(id: StringName) -> void
func clear_pin() -> void

## Drop both back to defaults.
func reset_hint_scope() -> void
```

`get_current_path` then:

1. If a pin is set and resolves to a real path, evaluate **only** that path and
   return it. It still needs `evaluate()` for bindings and cursor — pinning
   chooses the path, it does not bypass binding resolution.
2. Otherwise score only the allowed subset, unchanged from today.
3. If the pin names an unknown id, `push_error` and fall back to normal
   selection rather than returning null. A stale pin should degrade to working
   hints, not to no hints.

Everything downstream (`get_next_hint`, `get_next_hint_group`,
`get_hint_target`, `get_hint_group_target`) already funnels through the
`_cached_path` / `_cached_bindings` / `_cached_phase_index` trio and needs no
signature change.

### Where this state must NOT live

`LevelSolutionData` is a `Resource` loaded from a `.tres`, and Godot caches
resources by path. Two `Level` instances — or one level restarted — share the
same object. The existing `_cached_*` fields are safe because they are
recomputed on every hint request; **scope is not**, because it persists between
requests by design.

Recommended:

- Scope is transient and owned by the caller. `Level` sets it on level start and
  clears it on exit.
- `reset_hint_scope()` is called from `Level._ready()` unconditionally, so a
  stale pin from a previous level can never survive into a new one.
- Persistent state — which solutions the player has completed, which one they
  selected — lives in `SaveManager` and the UI layer, never on the resource.

If that split feels fragile, the alternative is threading a small
`HintScope` `RefCounted` through the five public entry points as a parameter.
More verbose, but it makes the lifetime obvious and removes the reset
requirement entirely. Worth considering if `Level` grows more hint call sites.

### Acceptance criteria

- Pinning a path makes `get_next_hint` return steps from that path even when
  another path scores strictly higher.
- With no pin and no allow-list, behaviour is byte-identical to today.
- An allow-list of one behaves identically to pinning that path.
- An empty allow-list means all paths, not no paths. (An explicit "no paths" is
  a caller bug; `get_next_hint` returning null forever is not a useful state.)
- Pinning an unknown id logs an error and falls back to normal selection.
- Scope does not survive a level restart.

### Design note — pinning on a dirty board

The cursor is a pure function of current store values, so pinning a path
mid-level does not reset anything. If the player's stores hold values the pinned
path never asks for, its cursor is 0 and hints start from phase 0 — which may
ask them to rebuild wiring they already have, or to re-latch a store.

That is the correct behaviour (the pinned path genuinely does start there), but
it is worth deciding at the UI level whether selecting a solution should offer
to reset the board first. Silently issuing hints that fight the current board
will read as a bug.

---

## CR-S3 — Accomplished-path detection

**Files:** `math-machine/HintSystem/level_solution_data.gd`
**Depends on:** CR-S1

### Behaviour

Challenge mode needs to know which solutions the player has actually completed.
The definition already exists in `LevelSolutionData`'s class docstring:

> A path is fully accomplished when its cursor reaches the final phase and every
> connection in that phase is satisfied.

Expose it:

```gdscript
func get_accomplished_path_ids(graph_canvas: GraphCanvas) -> Array[StringName]
```

Evaluate every path; a path qualifies when `evaluation.phase_index ==
get_phase_count() - 1` and every connection step in that phase is satisfied
under its own bindings. This is the same `evaluate()` call
`get_current_path` already makes, so cost is unchanged if the two are computed
together.

Returns an array, not a single id, because more than one path can qualify at
once — see below.

### Acceptance criteria

- A board matching a path's final configuration reports that path's id.
- A board one connection short of a final phase reports nothing.
- On a no-store level, completing the level reports the single path.
- The result is independent of `solution_paths` order.

### Open question for the designer

**Can two paths be accomplished simultaneously, and should both be credited?**

By construction paths have distinct final configurations (§19.10 keys on
exactly that), so normally at most one matches. But §19.10 deliberately drops
`to_port` from the key on commutative targets, and the hint system relaxes port
matching for Sum — so two paths differing *only* in which Sum port a wire lands
on collapse to one path anyway, and cannot both appear.

The residual case is a board that satisfies one path's final phase while the
stores also happen to hold another path's required values. Rare, but not
impossible on levels with several stores. Crediting everything genuinely
accomplished is the more generous reading and is what the return type above
assumes; crediting only the highest-scoring one is defensible too. Decide before
this is written to a save file.

---

## CR-S4 — Persisting per-solution completion

**Files:** `math-machine/Singletons/SaveManager/save_manager.gd`
**Depends on:** CR-S1, CR-S3

### Behaviour

Record completion as a set of `(level uid, path_id)` pairs. Bump
`SAVE_VERSION` to 3.

Migration from version 2 is lossy in one direction only and should stay that
way: a v2 save knows a level was completed but not *how*. Migrate it to
"level completed, no specific solutions credited" rather than guessing a path.
Inventing a `path_id` for a v2 save would credit a solution the player may never
have found.

Keep the existing `completed_level_uids` set alongside the new per-path data.
"Completed the level at all" and "completed solution X" are different questions
and the level-select screen only needs the first.

### Acceptance criteria

- A v2 save loads without error and reports zero completed solutions.
- Recording a solution for a level also marks the level completed.
- An unknown `path_id` in a save (because the level was regenerated and that
  solution no longer exists) is dropped quietly on load, not treated as an
  error. This will happen whenever a level's solution set legitimately changes.

---

## CR-S5 — Selecting a solution needs something to show

**Files:** UI layer; possibly the emitter
**Depends on:** CR-S1
**Priority:** lowest; needed only when the player-facing selector is built

### Behaviour

"Let the player pick a solution" needs each path to be *presentable*. A
`path_id` hash is not something to put in front of a player, and neither is
"path 3".

Two options, in increasing cost:

1. **Derived summary.** Build a label at runtime from the final phase: the
   store values the final network reads and which output each is wired to.
   `store_4` becomes "stores 9" and "stores 11"; `store_5` becomes "stores −10"
   and "stores 10". Cheap, needs no new data, and is exactly the distinction
   §19.10 keys on — so two paths always get different labels.

2. **Authored name.** An optional `@export var display_name: String` on
   `SolutionPath`, left blank by the emitter and filled in by hand where a level
   deserves it. Better copy, but it is per-path hand-authoring on generated
   files, which the pipeline has deliberately moved away from.

Recommend starting with (1) and adding (2) only if a level's solutions are
genuinely hard to tell apart from their end states.

### Note

Some paths really are near-identical from the player's side. `store_5`'s two
shortest paths share phases 0–4 and differ only in which of ±10 gets stored.
Whatever the selector shows, those two will look similar because they *are*
similar. That is a level design observation, not a UI problem.

---

## Ordering

```
CR-S0   (independent -- a live bug, land it first)

CR-S1 ─┬─ CR-S2 ────────── CR-S5
       └─ CR-S3 ─── CR-S4
```

CR-S0 is independent and should land first -- it is a live bug. CR-S1 blocks everything else. CR-S2 alone unblocks the testing need and the
"re-solve a chosen solution" need. CR-S3 and CR-S4 are the challenge-mode half
and can proceed in parallel with CR-S2.

## Testing a path before CR-S2 lands

Array order only breaks ties, so it cannot force a path that loses on score —
that is CR-S0. Until both land, `tools/hint_sim/hint_sim.py` will play any
emitted `.tres` by following its own hints and print the chosen path, cursor and
score per click. That is faster than clicking through the game and it is how
CR-S0 was diagnosed.

## Out of scope

- Changing the scoring function. Cursor-dominant lexicographic ordering stays as
  it is; these CRs constrain *which paths are considered*, not how they rank.
- The emitter's family/collapse rules. What counts as a distinct path is settled
  in `LEVEL_PIPELINE_CHANGE_REQUESTS.md` and §19.10.
- Challenge mode's own rules — scoring, ordering, unlocks. This document only
  supplies "which solutions has the player completed" and "guide me toward this
  one".
