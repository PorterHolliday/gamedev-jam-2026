# Math Machine — Tutorial Pacing Cut List (implemented)

**This has been applied to the project.** 65 levels → 43, same structural order (solo Add → solo Sum → Add+Sum combo → solo Subtract → Add+Subtract combo → Sum+Subtract combo → triple combo → solo Store → Store+2 combo → Store+3 combo). Every level below is identified by its filename so you can find it fast; positions refer to the *new* order unless marked "old #".

## What was actually changed, file by file

- **`Singletons/LevelManager/level_manager.tscn`** — removed 22 entries from `level_data_list` (and their now-unused `ext_resource` declarations). Save data is keyed by each level's resource UID, not by list position, so nobody's existing completion progress gets corrupted. One thing to be aware of when you push this live: a returning player's save still marks old levels complete by UID, but `SaveManager.get_deepest_incomplete_level_index()` walks the *new*, shorter list — so a returning player's "next incomplete level" may land somewhere slightly different than where they left off. Nothing will crash or lose data, but their level-select screen may look a little different on first load after the update.
- **`Screens/LevelSelectionScreen/level_selection_screen.tscn`** — trimmed each `GridContainer`'s `LevelButton` count to match the new per-mechanic totals (see below). Section divider labels ("Adjust Amount" / "Sum" / "Subtract" / "Hold Value") didn't need to change — they already mapped to "new mechanic introduced" boundaries, just with the old counts.
- **`Levels/LevelData/Sum/scenes/sum_1.tscn`** — removed the `TutorialPanel` and `NodeInfoTutorial` (+ its `Mouse`/`Pointer` children) nodes and their now-unused `ext_resource` entries. Sum's first level now has zero popups — pure gameplay, per your call to teach through level design rather than text. The ghost-wire preview on `GraphCanvas` (`tutorial_connection_data`) was left alone — that's a different, non-blocking system, not a forced popup.
- **The 22 cut levels' `.tres`/`.tscn` files were left in the project**, per your call — they're just no longer referenced by `LevelManager`, so they won't appear in-game. Nothing else in the project referenced them directly (I checked `level_manager.tscn` and each level's own `level_scene` pointer), but I didn't do an exhaustive project-wide search, so if Godot's editor flags an orphaned dependency on next open, that's expected and safe to ignore.
- **`Levels/LevelData/constant_sum/03_add_double_sum_b.tres`** — now points its `level_scene` at a new custom scene, `Levels/LevelData/constant_sum/scenes/03_add_double_sum_b.tscn`, instead of the generic `level.tscn`. See "Two popups re-added" below.
- **`Levels/LevelData/constant_sum/04_double_add_sum.tres`** — same deal, now points at `Levels/LevelData/constant_sum/scenes/04_double_add_sum.tscn`.
- **No tutorial text was added anywhere else** (Sum, Subtract, Store all left as you decided — trust level design and experimentation over popups).

## The 4 non-essential tutorial popups — cut entirely

These are dedicated levels whose only purpose is to force a popup + looping demo for a mechanic that's never required to solve anything. Cutting them removes 4 levels and ~4 forced pauses in the player's first 15 minutes. The info doesn't disappear — it's still in the How-To-Play screen (Help button), just not gating progress.

- **#3 `constant/add_value_3.tres`** — "Click a wire to remove it" (disconnect). Cut the whole level.
- **#7 `constant/add_value_7.tres`** — "Drag pieces to rearrange them." Cut the whole level.
- **#9 `constant/add_value_9.tres`** — "You can get a hint to see the next wire." Cut the whole level.
- **#11 `Sum/sum_2.tres`** — "Tutorials can be reread at any time" (points at Help button). This level teaches zero new Sum content — it exists purely to show this popup. Cut the whole level.

**`Sum/sum_1.tres`** (first Sum level) is a related but separate case: real content, kept, but it also forced a "Right-click a piece to learn how it works" node-info demo in the same breath as introducing Sum itself. The `NodeInfoTutorial` node was stripped and no replacement text was added — the level now just teaches Sum by having the player wire it up, consistent with your call to let node-info be discovered rather than taught.

## Two of those four, re-added later — based on real playtest feedback

After the initial cut, you flagged two of the four non-essential mechanics as worth re-teaching after all — not because they're required to solve anything, but because real playtesters specifically said they wanted to know about them sooner. Both reuse the exact same reusable tutorial components the original (now-cut) dedicated levels used — `DragTutorial` and `RemoveConnectionTutorial` — just grafted onto real levels instead of dedicated throwaway ones, and both fire at the same "board complexity" threshold: the first level with 3 operation nodes, where keeping track of what feeds what actually starts to matter.

- **Rearranging (drag) — re-added at `constant_sum/03_add_double_sum_b.tres`** (new position 11, the first 3-operation-node level in the new 43-level order). New custom scene `constant_sum/scenes/03_add_double_sum_b.tscn` adds a `TutorialPanel` ("Drag pieces to rearrange them.") and a `DragTutorial` node that loops a tween on the first operation node (graph node index 2, the first SUM) from its default spawn position out to `Vector2(704, 160)`, stopping the moment the player drags anything themselves. I picked the first operation node and an offset roughly up-and-right of the default column as a reasonable demo position — you said you'd reposition it in the editor if it lands wrong, so treat that `final_position` as a first guess, not a considered layout choice.
- **Disconnecting (click a wire) — re-added at `constant_sum/04_double_add_sum.tres`** (new position 12, right after the rearrange re-add). New custom scene `constant_sum/scenes/04_double_add_sum.tscn` adds the same `TutorialPanel` text as the original cut level ("Click a wire to remove it."), a `RemoveConnectionTutorial` node, and a `Pointer` child. `GraphCanvas.initial_connection_data` pre-wires two connections at level start (Input 0 → first ADD node, Input 1 → the SUM node) so there's something on screen to click; the `Pointer` sits at `Vector2(328, 220)`, roughly the midpoint of the Input-0-to-first-ADD wire — again, a best-effort placement for you to nudge in the editor.
- This landed as a general "boards get complex, here's how to manage that" pairing rather than something Store-specific. I dug through the code and every kept Store-section solution path — none of them structurally require a wire-click disconnect (replace-on-reconnect and click-a-filled-port-to-clear-it both already cover the "wire the wrong thing, fix it" case natively), so there's no code reason disconnect has to wait for Store. Teaching it here, at the same complexity threshold as rearrange, means the player already knows it by the time Store-section puzzles make it genuinely useful (wiring one path to capture a value, then rewiring a different path to the real targets).
- Explicitly **not** implemented, per your call ("just the tutorial level"): a hover-cue polish differentiating a filled port/wire from an empty one on hover (you noticed the hover highlight looks identical whether a wire is connected or not, which is real — `show_hover_fill()` in `graph_node_port.gd` always uses the same `hover_color`). That idea is parked, not built; flagging it here in case you want to revisit it later.

## Group-by-group cut list

**constant (solo Add Value) — 9 → 5.** Keep #1 (connect), #2 (multi-target win condition), #4 (chains two Add ops silently — worth keeping, it's a real new pattern with no text currently, fine as-is), #5 (multi-output wiring, essential). Cut #8 `add_value_8.tres` — no custom scene, no new pattern, redundant with #6/#5. (#3, #7, #9 already cut above.)

**Sum (solo Sum) — 5 → 3.** Keep #10 (first Sum, text swapped per above), #12 `sum_3.tres` (first double-Sum), #14 `sum_5.tres`. Cut #13 `sum_4.tres` — same shape as #14 (single input duplicated across two Sum nodes, 2 outputs), keep only one. (#11 already cut above.)

**constant_sum (Add+Sum combo) — 8 → 5.** This is your first real "combining is fun" content, so trimmed lightly. Keep `01_add_sum_pair_a` (simplest intro, 1 path), `02_add_sum_pair_b`, `03_add_double_sum_b`, `04_double_add_sum`, and `06_add_double_sum_b`. Cut `00_add_sum_pair_a` (near-duplicate of `01`, same shape, just more solution paths — pick one), `05_add_double_sum_a` and `07_add_double_sum` (both are the same SUM→ADD→SUM shape as `06` — three levels doing the same thing, keep the best one). `03` and `04` now also carry the re-added rearrange and disconnect tutorials respectively — see "Two of those four, re-added later" above.

**Subtract (solo Subtract) — 6 → 5.** No tutorial text here, by your call — you're teaching order-matters and negative-input-can-raise-the-output entirely through level design, not text, and I've left it that way. Kept `subtract_1` (baseline), `subtract_2` (same numbers as `subtract_1` but reversed input order → different output — this is the level that teaches order matters, not a duplicate, per your correction), `subtract_3` (multi-output chaining), `subtract_4` (negative input, -2 & 3 → 5 — explicitly called out as a must-keep), `subtract_5`. Cut only `subtract_6` (near-duplicate of `subtract_5`, same double-subtract shape).

**constant_subtract (Add+Subtract combo) — 7 → 4.** `02_add_subtract_pair_b` and `03_add_subtract_pair_b` are literally both named "pair_b" and are near-identical — keep one. `04_add_double_subtract_a`, `05_add_double_subtract_b`, and `06_add_double_subtract` are the same SUBTRACT→ADD→SUBTRACT shape three times over — keep one (recommend `06`, the most refined-looking of the three). Final keep: `01_add_subtract_pair_a`, `02_add_subtract_pair_b`, `03_double_add_subtract`, `06_add_double_subtract`.

**Sum_Subtract (Sum+Subtract combo) — 8 → 5.** `01` and `02` are a near-duplicate pair (same SUM+SUBTRACT shape) — keep one. `03`, `04`, `05`, and `07` are all the same SUM→SUBTRACT→SUM triple-op shape — that's four levels teaching the identical pattern; keep two (recommend `03` as the fullest first exposure and `07` as a later, harder rep with 2 outputs). Keep `06` (different shape: SUBTRACT→SUM→SUBTRACT) and `08_triple_sum_subtract` as your capstone (it's the most complex level in this group — 4 solution paths, 4 outputs). Final keep: `01`, `03`, `06`, `07`, `08`.

**constant_sum_subtract (triple combo) — 5 → 4.** Already lean. Keep `01_single_input_a`, `03_dual_input_a`, `05_dual_output` (distinct shape — 2 outputs), `06_single_input_b` (simplest, good as a breather). Cut `04_dual_input_b` — same shape as `03`, just more solution paths.

**store (solo Store) — 5 → 3.** `02_store_sum` and `03_store_sum` are the same SUM+STORE shape with different numbers — keep one. `04_store_subtract` and `05_store_subtract` are the same SUBTRACT+STORE shape — keep one. Final keep: `01_store_add` (the critical first exposure — see Store section below), `02_store_sum`, `04_store_subtract`.

**store_two (Store + 2nd mechanic) — 5 → 4.** `01_store_add_sum` is unusually open — 5 valid solution paths, the most of any level in the game — right at the point players are still absorbing Store itself. Recommend cutting it (or holding it in reserve for later if you want a genuinely hard level somewhere). Keep `02_store_add_subtract`, `03_store_double_sum`, `04_store_double_subtract`, `05_store_add_subtract_two_input`.

**store_three (Store + 3 mechanics) — 7 → 5.** `01_sum_add_add_c` and `02_sum_add_add_a` are the same op shape (ADD+ADD+SUM+STORE, both 3 solution paths, both 27 steps) — keep one. `06_store_double_sum_subtract` and `07_store_sum_double_subtract` are also near-identical (same 4 ops, same step/path counts, just different order) — keep one. Keep `01`, `03_subtract_add_add_a`, `04_subtract_add_add_b` (your single hardest level — 6 solution paths, 66 steps — good as the actual final level), `05_store_add_sum_subtract`, `06_store_double_sum_subtract`.

## Running total

constant 5 · Sum 3 · constant_sum 5 · Subtract 5 · constant_subtract 4 · Sum_Subtract 5 · constant_sum_subtract 4 · store 3 · store_two 4 · store_three 5 → **43 levels**, same order as before, first combo level still landing at the same relative point (right after solo Add+Sum), total run-time to reach the credits cut by about a third.

Mapped onto the level-select screen's mechanic sections (a new section starts once a new mechanic is introduced, same boundary logic the screen already used):

| Section | Old count | New count |
|---|---|---|
| Adjust Amount (solo Add) | 9 | 5 |
| Sum (Sum solo + Add+Sum combo) | 13 | 8 |
| Subtract (Subtract solo + Add+Subtract + Sum+Subtract + triple combo) | 26 | 18 |
| Hold Value (Store solo + Store combos) | 17 | 12 |
| **Total** | **65** | **43** |

`GridContainer` / `GridContainer2` / `GridContainer3` / `GridContainer4` in `level_selection_screen.tscn` now hold exactly 5 / 8 / 18 / 12 `LevelButton` nodes respectively.

## On the Store node — left as pure experimentation, still worth watching

You went with "say nothing, let the auto-disconnect + changed value clue them in" — no popup, no text change, nothing implemented here. My reasoning at the time, still worth keeping in mind: `store_node.gd` calls `_disconnect_input()` the instant a value lands, and `store_node.tscn` gives that moment no distinct visual or audio cue — it reuses the exact same wire-disappears look as a normal player-initiated disconnect. Every other disconnect in the game is something the *player* did by clicking; this is the one case where the *game* does it to them, unprompted, and it looks identical. A first-time player is about as likely to read that as "the game glitched and dropped my wire" as "the store locked in my value" — and if they read it as a glitch, they'll likely just rewire the same connection and hit the same "glitch" again.

I still think that's a defensible call, not a mistake — just something worth specifically watching for the first time you get eyes on a blind playtester: see whether they pause or backtrack at the moment the wire vanishes on that first Store level. If it turns out to be a real snag, the cheap fix (no new writing, just reusing what's already in the project) is a one-time glow/pulse on the Store node at the moment of capture — `HintVisuals` already has that pattern (`hint_tutorial.gd` pulses the hint button the same way), and the Store node's own `NodeInfo` panel already has the explanation sitting unused: "Hold Value" / "A" / "A, held." Nobody currently gets pointed at it — that's the fallback if pure silence doesn't hold up in testing.
