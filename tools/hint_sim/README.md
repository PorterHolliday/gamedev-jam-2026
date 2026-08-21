# Hint simulator

Plays an emitted `LevelData` `.tres` by following its own hints, and prints
which `SolutionPath` the hint system chooses at each click, with its cursor and
score.

```bash
cd tools/hint_sim
python3 hint_sim.py
```

It exists because "click the hint button and see what happens" is a slow and
unreliable way to reason about path selection, and because the interesting
behaviour only shows up deep into a level — the bug in CR-S0 of
`HINT_PATH_SELECTION_CHANGE_REQUESTS.md` first appears on click 13 of
`store_5`, after five latches.

## What it ports

Line for line, from `math-machine/HintSystem/`:

- `SolutionPath.evaluate`, `_cursor_for_bindings`, `_score_bindings`,
  `required_state`
- `SolutionStep.is_satisfied`, `_required_connection_count`
- `LevelSolutionData.get_current_path`, `get_next_hint`, `get_next_hint_group`
- `GraphCanvas.request_connection`'s sever-on-occupied-input rule, and
  `StoreNode.update_input`'s latch-then-auto-disconnect

Iteration order is preserved everywhere it can break a tie: live instances in
scene-child order, permutations picking `pool[0]` first, the same nesting in
`_combine_candidates`, and strict `>` so ties keep the incumbent. That matters —
several of these decisions are settled by tie-breaks, and a simulator that got
the order wrong would not reproduce the bug.

## What it does not model

Presentation only: glow, tweens, ghost values, audio. Nothing that affects which
path is chosen.

## Caveat

This is a **port, not the source of truth**. It agrees with the GDScript because
it was written against it, not because anything enforces that. If the two
disagree, the game is right and this file is stale. Re-read the GDScript before
trusting a surprising result — and if you change the scoring in
`level_solution_data.gd`, change it here too or the comparison harness silently
measures the old behaviour.
