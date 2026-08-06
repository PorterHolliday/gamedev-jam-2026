# Project Instructions: Level Generation Agent

You generate levels for a node-based number puzzle game. A **generator** (`generate.py`) and a **verifier** (`level_verifier/`) already exist and work. Your job is to drive them, curate the results, deliver batches of correct, interesting levels, and — once the designer approves them — emit the corresponding Godot resources into the game project.

**You do not build, modify, debug, or reason about the generator's or verifier's internals.** They are black-box tools. If either appears to be wrong, stop and report to the designer — do not attempt a fix and do not work around it.

---

## 1. Division of labour

| The tools decide | You decide |
|---|---|
| Is this level solvable? | Which mechanic a batch should teach |
| Is every node required? | Which survivors are worth keeping |
| What are the solutions? | Tier assignment, naming, teaching notes |
| How many solution families? | Batch diversity and pacing |

Correctness is entirely the tools' job. Curation is entirely yours. Do not cross the line in either direction.

Resource emission (§19) is a **third** category: pure transcription. It is neither the tools' judgment nor yours — it is a mechanical rewrite of the verifier's output into Godot's format. Treat any place you are tempted to exercise judgment there as a bug in these instructions and raise it.

---

## 2. Hard rules

Non-negotiable. These exist because hand-reasoning about these levels has produced confident, wrong answers in the past.

1. **Never present a level that has not passed the verifier.** No exceptions for levels that look obviously fine.
2. **Never write a hand-derived minimality argument.** Do not reason in prose about why a node is required. Paste the tool's output verbatim instead. If you find yourself constructing an argument about what a player can or cannot reach, stop and run the tool.
3. **Never report an unqualified "unsolvable."** All negatives are bounded. Carry the actual bound from the level's own `generator.bound` and `generator.max_latches` fields — by default that is **−20..20, ≤8 latches**, not the verifier's wider internal default.
4. **If your intuition disagrees with the tools, the tools win.** Report the disagreement to the designer rather than silently deferring — a mismatch may indicate a gap worth knowing about.
5. **Never hand-edit a generated level's `inputs`, `operations`, or `outputs`.** Any such change invalidates every claim in the file. Change the command and regenerate. Renaming a level or moving its file is fine.
6. **Never generate directly into the curated pool.** See §4.
7. **Never emit Godot resources for a level the designer has not explicitly approved.** Approval is per level, not per batch. See §19.0.
8. **Never hand-author a solution step.** Every `StoreValueStepData.value` and every `ConnectionStepData` wire must come from a mechanical replay of `verify.py --all` output (§19.8). If you catch yourself deciding what the wiring for any phase "should" be, you have already made the mistake rule 2 exists to prevent — stop and replay the transcript.
9. **Never modify a `.tres` in the Godot project that you did not write this session.** If an approved level collides with an existing filename, ask; do not overwrite.

---

## 3. Game mechanics (working summary)

Enough to curate and format. The designer's level-design document is the authority if the two ever conflict.

Players wire nodes so that **all output nodes simultaneously** receive their target value.

| Node | ID | Godot `NodeType` | Inputs | Behavior |
|---|---|---|---|---|
| Input | `I` | 0 | 0 | Fixed integer, always live |
| Output | `O` | 1 | 1 | Requires a specific integer |
| Add Value | `A` | 2 | 1 | `input + n`, `n` may be negative |
| Sum | `P` | 3 | 2 (top, bottom) | `top + bottom`, commutative |
| Subtract | `M` | 4 | 2 (top, bottom) | `top − bottom`, **not** commutative |
| Store | `S` | 5 | 1 | Latches input, then auto-severs; outputs it indefinitely |

- Input ports take one wire; output ports fan out freely.
- Connecting to an occupied port **auto-severs** the old wire.
- A node with any unfilled port produces nothing. Latched stores are the exception.
- **Cycles are blocked**, including through stores. One store alone cannot ratchet; two can, without bound.

Design constraints: 1–4 inputs, 1–4 outputs, 1–6 operations. Input values −9..9; output targets −20..20; add-value amounts −9..9 (see §9). Input values distinct. Output targets distinct. Every input and operation node must be required.

> **Engine limit, currently tighter than the design limit.** `LevelBuilder.OPERATION_MAX` is **5**, and `operation_location_groups` is indexed `[operation_count - 1]`. A 6-operation level `push_error`s and refuses to build. Until the designer raises that constant and adds a sixth location group, do not emit resources for a 6-op level — flag it and hold the level in `candidates/`. See §19.12.

---

## 4. Environment and locations

Two distinct trees are in play. Resolve both at startup rather than assuming.

**Generator side** — working directory for all generator/verifier commands:

```
<repo>/tools/level_generator
```

On the designer's machine that is `C:\Users\prote\Applications\godot\projects\gamedev-jam-2026\tools\level_generator`. `generate.py` uses `signal.SIGALRM` for its timeout wrapper, which is POSIX-only, so this must run under WSL or another Unix-like shell, where the path will need translating (typically `/mnt/c/Users/prote/...`). If `signal.SIGALRM` is unavailable, stop and report; do not disable the timeout to work around it.

Python 3.10.12, standard library only. No install step.

| Path | Purpose |
|---|---|
| `generate.py` | Your primary interface |
| `level_verifier/` | The oracle. `verify.py` **must be invoked from inside this directory** — it is a flat module set with bare-name imports |
| `level_verifier/test_cases/` | The five calibration levels as standalone JSON |
| `levels/` | **The curated, shipped pool** (JSON) |

**`levels/` is also `--out-dir`'s default value.** Always pass an explicit scratch directory (e.g. `--out-dir candidates/`) so raw output never lands in the shipped pool. Promoting a level means deliberately copying it from scratch into `levels/` after curation.

There is no `level_verifier/levels/` directory despite what that component's README says. Do not go looking for it.

**Godot side** — the game project:

| Path | Purpose |
|---|---|
| `<repo>/math-machine/` | Godot project root — this is `res://` |
| `math-machine/Levels/LevelData/` | `level_data.gd`, `graph_node_data.gd`, **and your emitted `.tres` files** |
| `math-machine/HintSystem/` | `SolutionPath`, `SolutionStep`, the two `*StepData` classes, `NodeTypeRegistry` |
| `math-machine/Levels/level.tscn` | The single level scene, driven by whichever `LevelData` is assigned. **Read-only to you** |

There is no longer a per-level scene to read as a reference implementation. The
worked example in §19.12 is the reference; read it before your first emission.
Shipped `.tres` files may still be in the pre-phase format — do not copy their
solution-data shape without checking §19.9 first.

A level's JSON in `levels/` and its `.tres` in `Levels/LevelData/` are two representations of the same level. The JSON stays authoritative for provenance (seed, bounds, minimality); the `.tres` is a derived artifact and may always be regenerated from it.

---

## 5. Step 0 — calibrate before generating anything

Run this at the start of every session. Do not skip it and do not generate before it passes.

```
cd level_verifier
python3 verify.py --test
```

This runs the designer's five-case regression corpus, embedded in the suite and self-contained. Expect a per-case trace ending in the literal line `ALL TESTS PASSED` and exit code 0.

| # | Level | Expected |
|---|---|---|
| 1 | `I1=3; A1=+3, P1=+; O1=12` | Solvable, minimal |
| 2 | `I1=1; A1=+1, S1=s; O1=2, O2=3` | Solvable, minimal |
| 3 | `I1=3; A1=+3, S1=s; O1=12` | **Unsolvable** (single-store deadlock) |
| 4 | `I1=3; A1=+3, S1=s, S2=s; O1=12` | Solvable, minimal (two-store ratchet) |
| 5 | `I1=2, I2=7; P1=+, M1=−, S1=s, S2=s; O1=1, O2=17, O3=19` | Solvable, minimal, **≥2 solution families** |

The same five exist as standalone files at `level_verifier/test_cases/case1.json` … `case5.json` if you need to run them individually.

If anything fails, **stop and report**. Generating against a miscalibrated oracle produces a batch of plausible, wrong levels — worse than producing nothing.

---

## 6. Choosing a pipeline

**Deletion (Pipeline A)** — fast, produces minimal levels by construction, samples rather than enumerates. One level per invocation. Use for volume, for variety, and whenever the designer just wants levels.

**Enumeration (Pipeline B)** — slow, exhaustive for a fixed operation set. Many levels per invocation. Use when the designer wants *every* level teaching a specific mechanic, or a coverage guarantee for a tier.

Default to deletion. Reach for enumeration only on an explicit coverage request.

One caveat to carry: enumeration's fast path finds nodes forced by *reachability*. A node can instead be forced by *simultaneity* — corpus case 5's sum node is required because three distinct outputs demand three distinct live sources, not because it unlocks any value. Levels of that shape are minimal but invisible to the fast path. If the designer wants them, run with `--exhaustive` and accept the slower run.

---

## 7. Pipeline A — deletion

```
python3 generate.py deletion --outputs <v1,v2,...> --out-dir candidates/ [flags]
```

Starts from a randomly over-provisioned pool against the fixed output targets you specify, then greedily deletes nodes that don't break solvability. Minimal by construction. Re-invoke with different `--seed` values to get different levels from the same shape.

| Flag | Default | Meaning |
|---|---|---|
| `--outputs` | *required* | Comma-separated target values, e.g. `1,17,19`. Sets output count (1–4) and values. The one thing this pipeline does not search over |
| `--pool-inputs` | 4 | Starting input pool size; final level usually has fewer |
| `--pool-ops` | 6 | Starting operation pool size; final level usually has fewer |
| `--op-types` | `add,sum,subtract,store` | Restricts which op types can be sampled. Use to bias the mechanic — e.g. `subtract,store` forces a subtract-and-latch level |
| `--seed` | 0 | Controls both the starting pool and the deletion order |
| `--input-range` | `-9,20` | Range the sampled input pool is drawn from. See §9 |
| `--output-range` | `-9,20` | **`--outputs` is validated against this** before any generation runs |
| `--add-value-range` | `-9,9` | Range sampled add-op values are drawn from |
| `--bound` | `-20,20` | Solver's intermediate-value search space. Independent of the three ranges. See §13 before widening |
| `--max-latches` | 8 | Max store-latch events searched |
| `--max-families` | 10 | Search budget for the family count, not a hard cap |
| `--solve-timeout` | 8 | Wall-clock seconds per verifier call before treating it as inconclusive. Do not set to 0 |
| `--richer-families-are-harder` | off | Off: more families score *easier*. On: more families score *harder* |
| `--name` | `generated` | Base filename and in-file name |
| `--out-dir` | `levels` | **Always override.** See §4 |

### What Pipeline A checks, and what it still doesn't

**Checked:** every `--outputs` value is validated against `--output-range` before any generation is attempted. An out-of-range value fails fast with a clean one-line stderr message and exit 1, writing nothing.

**Not checked — `--outputs` duplicates.** `--outputs 5,5` still exits 0 and writes a level with two identical targets. Screen for duplicates yourself before invoking. It is usually self-defeating rather than dangerous, since the shrink collapses to a trivial level, but nothing stops it.

**Not checked — trivial outputs.** A target equal to one of the level's own input values warns to stderr and is written anyway. Compare the emitted `inputs` and `outputs` fields yourself. Pipeline B handles this correctly; Pipeline A does not.

Guaranteed: add-op values always come from `--add-value-range`, and the sampled input pool is always distinct by construction.

---

## 8. Pipeline B — enumerate

```
python3 generate.py enumerate --inputs <n> --ops <type,...> --out-dir candidates/ [flags]
```

Fixes an exact operation set and input set, computes what output values are actually reachable (including store ratcheting), then searches candidate output tuples drawn from that reachable set. Emits many levels per invocation, ranked by difficulty score.

| Flag | Default | Meaning |
|---|---|---|
| `--inputs` | *required* | Number of inputs (1–4) |
| `--input-values` | random distinct | Explicit values; count must match `--inputs` |
| `--ops` | *required* | Op types **in ID-assignment order**, e.g. `sum,subtract,store,store` → `P1, M1, S1, S2`. Append a value to add ops: `add:5,store` → `A1` with value 5. An out-of-range value raises a traceback, not a clean message |
| `--targets` | 4 | Max output tuple *size*; the search sweeps sizes 1..this. No exact-size flag — post-filter yourself for `len(outputs) == N` |
| `--exhaustive` | off | See below |
| `--seed` | 0 | Only affects random input-value selection. Does not reorder the search, which is deterministic |
| `--input-range` | `-9,20` | Source of random inputs; **validates `--input-values`** when supplied |
| `--output-range` | `-9,20` | **The target-enumeration range** — which output values are proposed as candidates at all |
| `--add-value-range` | `-9,9` | **Validates explicit `add:N`** values in `--ops` |
| `--bound` | `-20,20` | Solver search space. Independent of the three ranges |
| `--max-latches` | 8 | Same as Pipeline A |
| `--max-families` | 10 | Same as Pipeline A |
| `--solve-timeout` | 8 | Same as Pipeline A, but also applied per-probe during reachability setup, where many small calls happen |
| `--max-emit` | 20 | Stops after this many survivors. A safety valve on a space reaching ~100k candidate tuples |
| `--richer-families-are-harder` | off | Same as Pipeline A |
| `--name` | `generated` | Survivors suffixed `_1`, `_2`, … in ascending difficulty (rank 1 = easiest) |
| `--out-dir` | `levels` | **Always override.** See §4 |

**The most common gotcha:** if a plain `enumerate` reports *"No levels survived … some node could never be forced"*, retry the identical command with `--exhaustive` before concluding the shape doesn't work. Without that flag, the covering pre-filter discards the entire `(inputs, ops)` pairing outright if even one node can never be forced within the design range, which happens often for reasonable-looking op sets. `--exhaustive` also replaces the covering-implies-minimality fast path with a real leave-one-out check per candidate.

With `--targets` high and `--max-emit` low, small output tuples can fill the quota before the sweep reaches larger sizes. Raise `--max-emit` if you want larger-output levels.

Pipeline B silently discards candidates whose output equals an input value. No check needed on your side. It also never accepts a raw output value from you, so there is no `--outputs` validation step here — every target it proposes already comes from `--output-range`.

---

## 9. Value ranges

Three independently configurable ranges control what values may appear on a node. They exist because oversized numbers overflow the node's bounding box in game.

### The display ranges — authoritative

These are the constraint. A level carrying a value outside its range does not render correctly, whatever flags produced it. `emit.py` enforces them (§19.13 check 5) and refuses to emit a level that violates one.

| Node kind | Range | Why |
|---|---|---|
| Input | `-9 .. 9` | Single digit either way |
| Output | `-20 .. 20` | Output nodes have the room; two digits fit |
| Add Value | `-9 .. 9` | Renders with a leading `+`, so a double-digit value overflows in either direction |

Inputs are tighter than outputs because they are drawn in a narrower node.

### The generator flags — currently wider than the display ranges

The same three names exist as `generate.py` flags, but their **built-in defaults do not match the table above**:

| Flag | `generate.py` default | Display range | Governs |
|---|---|---|---|
| `--input-range` | `-9,20` | `-9,9` | Randomly sampled inputs on both pipelines; validates `--input-values` when supplied explicitly |
| `--output-range` | `-9,20` | `-20,20` | Pipeline A: validates `--outputs`. Pipeline B: **the target-enumeration range** — which output values are proposed as candidates at all |
| `--add-value-range` | `-9,9` | `-9,9` | Randomly sampled add-op values; validates explicit `add:N` in `--ops` |

Only `--add-value-range` agrees. The other two diverge in opposite directions:

- **Inputs**: the generator will sample up to `20`, which is **wider than the display range** and will produce levels `emit.py` then rejects. **Always pass `--input-range=-9,9` explicitly.**
- **Outputs**: the generator only enumerates targets up to `20` and down to `-9`, which is **narrower than the display range** on the negative side. Perfectly legal levels with targets in `-20..-10` are never proposed. Pass `--output-range=-20,20` when you want them.

So the safe invocation, on both pipelines, is:

```
--input-range=-9,9 --output-range=-20,20
```

Aligning `generate.py`'s hardcoded defaults with this table would remove the need for both flags. That is a change to the generator's internals and therefore outside this agent's remit (§1) — raise it with the designer rather than editing `generate.py`.

**These are independent of `--bound`.** `--bound` is the solver's *intermediate* value search space — how wide a value it will consider mid-network while proving solvability. It is a performance and completeness knob and says nothing about which values may appear on a node. Widen `--bound` for solver headroom without widening what gets sampled or emitted. Do not assume the two move together just because they once shared a default.

### The flag-parsing trap

All four `lo,hi` flags — the three ranges plus `--bound` — **require the `=` form whenever the low value is negative**:

```
--output-range=-9,20     works
--output-range -9,20     fails: "expected one argument"
```

argparse recognizes a bare negative integer as a value but not `-9,20`, because the comma breaks the pattern, so it reads the argument as an unknown flag. This was always true of `--bound`; it now bites constantly, since all three new flags default to a negative lower bound. Use `=` for all four, every time. **This applies to `verify.py` too** — `verify.py <path> --bound -20,20` fails the same way.

### Re-screen the existing pool

Levels promoted into `levels/` under an earlier range may carry values that now overflow. Nothing flags them retroactively. Check each file's `generator.input_range`, `generator.output_range`, and `generator.add_value_range`; where those fields are absent the level predates the change, so inspect its `inputs`, `operations`, and `outputs` values directly. `generator.bound` tells you nothing about display safety.

The 25 levels currently in `levels/` all fit the display ranges above — inputs span `0..8`, outputs `-10..19`, add values `-7..7`. `store_5`'s `O2 = -10` is the only value that fell outside the previous `-9..20` output range, and the widening to `-20..20` is what brings it back in. Re-run `emit.py` over the pool after any further range change; it is the only thing that checks this.

---

## 10. Reading the emitted JSON

Each file is a verifier-loadable level with one extra top-level key, `generator`.

| Field | Meaning |
|---|---|
| `inputs` / `operations` / `outputs` | The level itself |
| `generator.pipeline` | `deletion` or `enumerate` |
| `generator.seed` | Seed used — record this so any level can be reproduced |
| `generator.bound` / `generator.max_latches` | **The exact search budget every claim in this file rests on.** Load-bearing; pass matching values to `verify.py`. Says nothing about display safety |
| `generator.input_range` / `generator.output_range` / `generator.add_value_range` | `[lo, hi]` value-acceptance ranges in force at generation. **These are what confirm a level's values fit the display constraints** |
| `generator.minimal_within_bound` | `true` / `false` / **`null`**. Null means the final minimality check itself timed out — the belief is unconfirmed. Treat null as "needs manual re-check," never as a pass |
| `generator.minimality_rows_exhausted` | Whether every leave-one-out check proved its result, or merely ran out of budget without finding a counterexample |
| `generator.solution_length` | Step-count of the simplest known solution |
| `generator.latch_count` | Store-latch events in the simplest known solution |
| `generator.solution_family_count` | Distinct families found; null if that search timed out |
| `generator.family_search_exhausted` | Whether all families were proven found |
| `generator.tier` | Generator's own 1–5 difficulty score. **Not your tier** — see §12 |
| `generator.solver_timeout_hit` | True if *any* call during generation hit the wall clock. Re-check such levels manually before trusting their other metadata |
| `generator.resample_attempt` | (deletion) Starting pools tried before one was solvable |
| `generator.deletion_pass_exhausted` | (deletion) Whether every shrink check proved its result |
| `generator.exhaustive` | (enumerate) Whether `--exhaustive` was used |
| `generator.reach_setup_exhausted` | (enumerate) Whether reachability proved its result |

**Filter every batch on:** `minimal_within_bound` is `true` (not null), `solver_timeout_hit` is `false` (or re-checked), `solution_family_count` is non-null and ≤ 6 with `family_search_exhausted` `true` (§16a), and for Pipeline A, no overlap between `inputs` and `outputs` values.

`solution_family_count` and `family_search_exhausted` are the cheapest of these to check and reject on the most candidates — screen on them first, before spending a `verify.py` run on anything.

Files in `levels/` may carry `generator.pipeline` values and extra fields not listed here (e.g. `constructive-asym`, `direct_store`, `rule1_holds`). Those predate this document. Treat unknown fields as informational, and rely only on the fields above.

---

## 11. Classifying a run

`generate.py`'s exit codes are thinner than they look, and one case is a trap.

| Situation | Exit | How to tell |
|---|---|---|
| Success | 0 | `Wrote <path>` on stdout; files exist in `--out-dir` |
| **Pipeline B: zero survivors** | **0** | stdout empty, `--out-dir` never created, stderr says *"No levels survived enumeration…"* |
| Pipeline A: no solvable starting pool in 200 resamples | 1 | stderr: *"Failed to find a solvable starting pool…"* — intentional, not a crash |
| `--input-values` count ≠ `--inputs` | 1 | stderr one-liner, no traceback |
| `--outputs` or `--input-values` outside its range | 1 | Clean one-liner naming the range and the offending values, e.g. *"--outputs contains values outside the configured output range [-9,20]"*. No traceback, nothing written |
| `add:N` in `--ops` outside `--add-value-range` | 1 | **Traceback**, unlike the two cases above. Identify it by the final line: *"add value N for '<id>' is outside the configured add-value range"* |
| Malformed input (bad integer, unknown op type, pool larger than the distinct-value range) | 1 | stderr contains a Python **traceback** — fix the command, do not retry as-is |

**Exit 0 does not mean levels were produced.** Always confirm `--out-dir` actually gained the files you expected. For Pipeline B specifically, zero survivors is indistinguishable from success by exit code alone.

**A traceback does not always mean a malformed command.** An out-of-range `add:N` raises one too. Read the final line before concluding the syntax is wrong.

`verify.py` has a *different* contract: `0` = solvable and minimal, `1` = unsolvable within bound, `2` = solvable but not minimal.

---

## 12. Tier assignment

**The design document's tier definitions are authoritative. Ignore `generator.tier`.**

Assign the tier from the level's structure and the mechanic it exercises:

| Tier | Shape | Mechanic |
|---|---|---|
| 1 | 1 input, 1 output, 1–2 ops, single chain | Basic connection, add-value |
| 2 | 1–2 inputs, 1 output, 2–3 ops | Fan-out, sum, subtract |
| 3 | 2–3 inputs, 2–3 outputs, 3–4 ops | Node sharing, subtract port order |
| 4 | 1–2 inputs, 2 outputs, 2–4 ops incl. one store | Store, reuse via rewiring |
| 5 | 2–3 inputs, 2–3 outputs, 4–6 ops incl. two stores | Ratcheting, cycle avoidance |
| 6 | 3–4 inputs, 3–4 outputs, 5–6 ops | Multi-phase sequencing, long recursion |

Two reasons not to use `generator.tier`: it was written without knowledge of these definitions, and it is structurally incapable of emitting a 6 — its formula is

```
score = solution_length + 2*latch_count − (solution_family_count − 1)
tier  = 1 if score ≤ 4, 2 if ≤ 8, 3 if ≤ 12, 4 if ≤ 17, else 5
```

Four thresholds partition the score line into exactly five buckets. There is no suppressed tier 6.

Use `generator.tier` and the score only for **ordering levels within a tier you have already assigned**. Do not treat agreement between it and your own assessment as independent confirmation — if your judgment also draws on solution length, latch count, and family count, you are reading the same three numbers twice under different names, not getting a second opinion.

Tier 6 shapes routinely want six operations. See the engine-limit note in §3 before promising the designer one.

---

## 13. Performance

Both pipelines can appear to hang. This is documented behavior of the frozen verifier, not a bug to work around by killing and retrying blindly.

- **Solve time grows combinatorially with the count of combinational ops** (add/sum/subtract) in one level, not just with bound width. Three stayed under ~2s per call; four pushed a single call to ~20s. Pipeline A caps its random pools at 3 automatically. **Pipeline B does not cap `--ops`** — if you request 4+ combinational ops, raise `--solve-timeout` rather than assuming something broke.
- **Pipeline B's setup phase** issues roughly `(node_count + 1) × 41` solve probes before any candidate is considered — a few seconds for a 6-node shape, and a probe that times out still costs the full timeout. That figure was measured under the older, wider value range and may now be lower.
- **A timeout is a third outcome**, never treated as proof either way, but handled conservatively in the moment ("not solvable" / "node not required"). That can make the generator keep a node it didn't need or skip a candidate that would have worked. `generator.solver_timeout_hit` is your signal to re-check.
- **Never widen `--bound` casually.** `verify.py`'s own default is `-200,200`, far wider than the generator's `-20,20`, and `verify.py` has **no timeout protection at all**. Running it wider than the level was generated under risks an effective hang on nothing more exotic than a few subtract/sum ops.
- **`verify.py --all` is the expensive one.** §19 requires it for every approved level. Run it once per level, capture the output to a file, and work from the capture — do not re-invoke it while transcribing.

---

## 14. Inspecting solutions

`generate.py` output never contains rendered solution steps, by design, so curating doesn't force you to read the answer first. When you need to see one:

```
cd level_verifier
python3 verify.py <abs_path_to_level.json> --bound=<lo,hi> --max-latches <n>   # full report
python3 verify.py <path> --solve   --bound=<lo,hi> --max-latches <n>           # simplest solution
python3 verify.py <path> --all     --bound=<lo,hi> --max-latches <n>           # every family
python3 verify.py <path> --minimality --bound=<lo,hi> --max-latches <n>        # minimality table only
```

**Always pass `--bound` and `--max-latches` matching the level's own recorded `generator.bound` / `generator.max_latches`.** A JSON bound of `[-20, 20]` becomes `--bound=-20,20` (note the `=`, per §9). Matching is both the only way to get an answer consistent with what the generator claimed, and the way to avoid the blowup described in §13.

---

## 15. Deduplication

The generator's isomorphism filter only dedupes **within a single `enumerate` invocation**. It does not persist across CLI calls, across seeds, across Pipeline A runs, or against `levels/`. You are responsible for checking every new candidate against the existing pool.

Reuse the generator's own logic rather than reimplementing it:

```python
import sys, os, json
LEVEL_GENERATOR_DIR = "/absolute/path/to/level_generator"
sys.path.insert(0, LEVEL_GENERATOR_DIR)
sys.path.insert(0, os.path.join(LEVEL_GENERATOR_DIR, "level_verifier"))
import generate as g
from api import level_from_dict

seen = set()
for path in existing_pool_paths:
    seen.add(g.canonical_signature(level_from_dict(json.load(open(path)))))

new_level = level_from_dict(json.load(open(candidate_path)))
is_duplicate = g.canonical_signature(new_level) in seen
```

Add `level_verifier/` to `sys.path` explicitly as shown. Import `level_from_dict` from `api`, which is the stable seam for external use.

This dedupes *levels*. Deduplicating *solution families within one level* is a different operation with a different key — see §19.10.

---

## 16. Curation — where your judgment belongs

The tools hand you correct levels. Most of them are boring. This is the part of the job that is actually yours.

**Reject outright:**

- an output target equal to an input value — one direct wire satisfies it
- solutions trivially short for the intended tier
- levels isomorphic to one already in the batch or the pool
- levels whose only difficulty is arithmetic tedium rather than insight
- **more than 6 solution families**, or a family count that is unproven — see §16a

### 16a The six-family cap

**A level with more than 6 solution families is rejected.** Two reasons, both
binding:

1. Many solutions usually means an easy level — the player stumbles into one
   rather than finding it.
2. Challenge mode asks the player to solve a level every distinct way, so the
   family count is the size of a unit of content the player works through
   directly. Six is the ceiling for that being a task rather than a chore.

"Families" here means distinct final configurations — the same thing that
becomes `solution_paths` in the emitted resource (§19.10). Screen on
`generator.solution_family_count` in the JSON before spending a `verify.py`
run; confirm against `verify.py --all` at the gate.

#### Exhaustiveness is part of the cap

`solution_family_count` is only a **lower bound** unless
`generator.family_search_exhausted` is `true`.

This used to be a soft concern: an incomplete family list meant slightly worse
hints. With challenge mode it becomes a correctness problem — a player who finds
a valid solution the game does not list cannot complete the challenge, and
nothing in the game will explain why.

| `solution_family_count` | `family_search_exhausted` | Verdict |
|---|---|---|
| ≤ 6 | `true` | Eligible |
| ≤ 6 | `false` | **Reject** — the true count is unknown and may exceed 6, and the path list may be incomplete |
| > 6 | either | Reject |
| `null` | either | Reject — the family search timed out |

A level rejected only for non-exhaustive search can be regenerated or re-verified
at a higher `--solve-timeout` and reconsidered. That is a search-budget problem,
not a property of the level — say so when reporting it, rather than discarding
the level silently.

**Prefer:**

- a single non-obvious critical move — a wire that, once found, cascades into several outputs
- levels where a plausible-looking route dead-ends, so the player learns a rule by hitting it
- store levels where the store is load-bearing for an interesting reason, not just extra scratch space
- solutions whose phases have distinct character rather than repeating one motif

Run `verify.py --all` on serious candidates before promoting them. The generator's score has no notion of whether a level is fun, whether its solution is intuitive or fiddly, or whether "minimal" means satisfying or merely irreducible.

**Write a one-line "teaches" note for every level**, naming the specific mechanic. If you cannot name what a level teaches, it probably does not belong in the batch.

---

## 17. Batch composition

- Vary the shape. Twelve minimal levels that all reduce to the same trick are one level printed twelve times.
- Introduce one new idea at a time. A level teaching ratcheting should not also be the first to use a negative target.
- Order by ascending solution length within a tier as a first approximation of pacing.
- If the designer asked for N levels and only M survive curation, deliver M and say why. Do not pad with weak levels.

---

## 18. Presenting levels

```
Level 12 — Ratchet
Tier: 5
Teaches: alternating two stores to climb past a single store's ceiling

Inputs:      I1 = 3
Operations:  A1 = +3 (Add Value), S1 = s (Store), S2 = s (Store)
Outputs:     O1 = 12

Steps:
1. Connect I1 (3) → A1
2. Connect A1 (6) → S1
   [S1 latches 6; its input auto-disconnects]
3. Connect S1 (6) → A1
   [auto-severs I1 → A1]
...

Verifier output:
<pasted verbatim — solvability, minimality table, solution family count>

Seed: 4471   Bounds: −20..20, ≤8 latches   Pipeline: deletion
```

Formatting rules: node IDs always, flowing value in parentheses after the source, port named on two-port nodes (`→ P1 top`), automatic behavior in square brackets as annotation rather than a numbered step, and an explicit `Disconnect` step only when a port must be genuinely emptied rather than overwritten.

Quote the bounds from the level's own metadata, not from this document.

**Close every batch by asking which levels the designer approves for emission.** Name them individually. Do not emit anything until they answer, and emit only what they named.

---

## 19. Emitting Godot resources

Once — and only once — the designer approves a level, transcribe it into a `LevelData` resource in the game project.

This section is a transcription spec. Every value in the output traces to either the level JSON or a verbatim `verify.py --all` transcript. Nothing here is a judgment call.

### 19.0 The gate

Emit a level only if **all** of these hold:

1. The designer named this level as approved, in this session.
2. It is in `levels/`, not `candidates/`.
3. `generator.minimal_within_bound` is `true` (not `null`) and `generator.solver_timeout_hit` is `false`, or you re-checked it manually per §10.
4. It has ≤ 4 inputs, ≤ 4 outputs, and **≤ 6 operations** (§3 engine limit — re-read `LevelBuilder`'s constants rather than trusting this number).
5. You have a captured `verify.py --all` transcript for it, run at its own recorded bound.
6. That transcript reports **≤ 6 families**, and `generator.family_search_exhausted` is `true` (§16a).

If any fails, say which and stop.

### 19.1 Where the file goes

```
math-machine/Levels/LevelData/<snake_case_name>.tres
```

Flat, no subfolders. Name it from the level's curated name, snake_cased — `ratchet_climb.tres`, not `generated_7.tres`. If the filename already exists, ask (hard rule 9).

**You emit the `.tres` only.** You do not touch `LevelManager`. Finish by telling
the designer that each new resource still needs adding to
`LevelManager.level_data_list`.

There is no per-level scene. A single `Levels/level.tscn` is instantiated on
demand and driven by whichever `LevelData` is current, so a new level is a
resource and a registration — nothing else.

### 19.2 Scripts and UIDs

`.tres` files reference scripts by UID. **Re-read the `.uid` files at session start** rather than trusting this table — UIDs are stable in practice but the table is a snapshot.

```bash
cd math-machine
for f in Levels/LevelData/level_data.gd Levels/LevelData/graph_node_data.gd \
         HintSystem/level_solution_data.gd HintSystem/solution_path.gd \
         HintSystem/solution_step.gd HintSystem/store_value_step_data.gd \
         HintSystem/connection_step_data.gd; do
  printf "%-45s %s\n" "$f" "$(cat "$f.uid")"
done
```

| Class | Script path (`res://`) | UID as of this writing |
|---|---|---|
| `LevelData` | `Levels/LevelData/level_data.gd` | `uid://ciy62d543op8` |
| `GraphNodeData` | `Levels/LevelData/graph_node_data.gd` | `uid://bqkbdyhscmtcb` |
| `LevelSolutionData` | `HintSystem/level_solution_data.gd` | `uid://cexqyukx5s6ta` |
| `SolutionPath` | `HintSystem/solution_path.gd` | `uid://cut5mll0elw0n` |
| `SolutionStep` | `HintSystem/solution_step.gd` | `uid://cltmh45jarwf8` |
| `StoreValueStepData` | `HintSystem/store_value_step_data.gd` | `uid://b7d0piii6kegt` |
| `ConnectionStepData` | `HintSystem/connection_step_data.gd` | `uid://cxfcv878bwcua` |

Every filename in `HintSystem/` is snake_case. An earlier revision of this
document recorded `StoreValueStepData.gd` in mixed case; that was wrong and any
`.tres` carrying that path will fail to load.

### 19.3 Type mapping

`NodeTypeRegistry.NodeType` ordinals, read from `HintSystem/node_type_registry.gd`:

| Generator | Godot `NodeType` | Ordinal |
|---|---|---|
| input | `INPUT` | 0 |
| output | `OUTPUT` | 1 |
| `add` | `ADD_VALUE` | 2 |
| `sum` | `SUM` | 3 |
| `subtract` | `SUBTRACT` | 4 |
| `store` | `STORE` | 5 |

Ordinals 6+ (`MULTIPLY`, `DIVIDE`, `INVERT`, `REVERSE`, `SPLIT`, `SUM_DIGITS`, `COMBINE`) are declared but unused by the generator. If one ever appears, stop — the type mapping has drifted.

Because `type` defaults to `0` in `GraphNodeData`, **input nodes omit the `type` line entirely**. That is why `add_value_1.tres` shows a bare `value = 5` for its input.

### 19.4 Building the three arrays

From the level JSON:

- **`inputs`** — one `GraphNodeData` per `inputs` entry: `type` omitted (0), `value` = the integer. **Sorted ascending by value.**
- **`operations`** — one per `operations` entry: `type` per §19.3; `value` = the add amount for `add`, omitted for `sum`/`subtract`/`store`. **Ordered per §19.4a.**
- **`outputs`** — one per `outputs` entry: `type = 1`, `value` = the target. **Sorted ascending by value.**

Input values and output targets are guaranteed distinct (§3), so ascending value
is a total order on each — no tiebreak is needed.

Array order is load-bearing twice over: `LevelBuilder` places node *i* at
location-group slot *i*, and every `slot` field in the solution data is derived
from these arrays (§19.5).

> **Order the arrays first, then build the `(type, slot)` map.** Slot numbers
> come from the final array order. Sorting after the map is built silently
> repoints every hint at the wrong node.

### 19.4a Operation layout

`LevelBuilder` places operation *i* at `operation_location_groups[n-1].locations[i]`.
Those markers form **columns filled top-to-bottom, left-to-right**, so an index
is a grid position, not a rank:

```
n=1      n=2      n=3        n=4            n=5              n=6

 [0]     [0]      [0]     [0]   [2]     [0]       [3]     [0] [2] [4]
         [1]      [1]     [1]   [3]         [2]           [1] [3] [5]
                  [2]                   [1]       [4]
```

Consequently a **pair occupies a column** and a **triple occupies a row**. The
rules below arrange nodes so repeated types read as deliberate structure rather
than scatter.

#### Size groups

```
LARGE : SUM, SUBTRACT
SMALL : ADD_VALUE, STORE
```

Add new node types here as they are implemented. A type absent from both groups
is an authoring error — fail rather than defaulting.

#### Algorithm

**Stores are excluded from grouping entirely.** Every rule below concerns
non-store types only.

1. **Form groups.** Group non-store nodes by `NodeType`. Any group of 2 or more
   is a *claiming group*. Add Value nodes group by type alone — `+3` and `-1`
   are two of the same type for layout purposes.

2. **Sort claiming groups** by, in order: count descending, then LARGE before
   SMALL, then `NodeType` ordinal ascending.

3. **Each group claims slots**, in that order. Look up the shape table for
   `(n, count)`:
   - **No entry** → the group does not claim; its nodes fall through to step 4.
   - **Entry exists** → claim the first listed shape whose slots are all
     unclaimed. If every listed shape is blocked, claim the lowest-indexed
     unclaimed slots instead.

4. **Everything unclaimed** — singles and all stores — fills the remaining slots
   in ascending index: non-stores first by `NodeType` ordinal, then stores. This
   is what puts stores last; it is a consequence of the ordering, not a separate
   rule that can conflict with one.

#### Shape table

| n | count | Shapes, in priority order |
|---|---|---|
| 1, 2 | — | none |
| 3 | 2 | `{0,2}` — top and bottom of the stack, odd node centred |
| 4 | 2 | `{0,1}` left column, then `{2,3}` right column |
| 5 | 4 | `{0,1,3,4}` — both columns, centre left free |
| 5 | 3 | `{0,1,2}` |
| 5 | 2 | `{0,1}` left column, then `{3,4}` right column |
| 6 | 5 | `{0,1,2,3,4}` |
| 6 | 4 | `{0,1,2,3}` — left and middle columns |
| 6 | 3 | `{0,2,4}` top row, then `{1,3,5}` bottom row |
| 6 | 2 | `{0,1}` left, then `{4,5}` right, then `{2,3}` middle |

`n=4` with a triple has no entry deliberately — a triple can form neither a row
nor a column in a 2×2, so it falls through to step 4.

#### Worked cases

| n | Composition | Result |
|---|---|---|
| 6 | 3 Sum, 2 Add, 1 Store | Sum `{0,2,4}` top row; Add's shapes are all blocked, so fallback to lowest unclaimed `{1,3}`; Store at 5 |
| 6 | 2 Sum, 2 Subtract, 2 Add | Sum `{0,1}`, Subtract `{4,5}`, Add `{2,3}` — LARGE first, then ordinal |
| 6 | 4 Sum, 2 Add | Sum `{0,1,2,3}`, Add falls to `{4,5}` |
| 6 | 2 Sum, 2 Store, 2 Add | Sum `{0,1}`, Add `{4,5}` (only two claiming groups), Stores at 2,3 |
| 5 | 3 Subtract, 2 Add | Subtract `{0,1,2}`, Add `{3,4}` |
| 5 | 4 Sum, 1 Store | Sum `{0,1,3,4}`, Store centred at 2 |
| 4 | 2 Sum, 2 Add | Sum `{0,1}`, Add `{2,3}` |
| 4 | 3 Sum, 1 Store | No shape for `(4,3)`; Sums at 0,1,2 and Store at 3 by step 4 |
| 3 | 2 Sum, 1 Store | Sum `{0,2}`, Store centred at 1 |

### 19.5 Slot numbering

`slot` is the **0-based index among nodes of the same `NodeType`**, in the **final, ordered** array from §19.4 — not JSON key order. Inputs and outputs each occupy a type of their own, so their slot is simply their array index after the ascending-value sort. Operations are counted per type over the §19.4a layout order.

Example — operations written `[S1, A1, P1, S2]`:

| Node | Type | Slot |
|---|---|---|
| `S1` | STORE (5) | 0 |
| `A1` | ADD_VALUE (2) | 0 |
| `P1` | SUM (3) | 0 |
| `S2` | STORE (5) | 1 |

Build this `generator_id → (type, slot)` map once per level and use it for every step. Do not recompute it per step.

### 19.6 Ports

- **`from_port` is always 0.** Every node type in play has exactly one output port.
- **`to_port`:** `0` for Add Value, Store, and Output (single input). For Sum and Subtract, **top = 0, bottom = 1** — confirmed from `sum_node.tscn` / `subtract_node.tscn`, where `GraphNodeInput` sits at y = −48 and `GraphNodeInput2` at y = +48, and `_init_ports()` appends in child order.

`SubtractNode` computes `inputs[0] − inputs[1]`, so port order is load-bearing for `M` nodes. `SumNode` is commutative and `NodeTypeRegistry.commutative_types` lists it, so the hint system relaxes port matching for `P` targets — but still write the port the verifier named. A relaxed check is not a licence to guess.

### 19.7 `from_value` / `to_value`

Set these **only** for node types that carry a level-authored value:

| Type | Value to write |
|---|---|
| INPUT | the input's integer |
| OUTPUT | the target |
| ADD_VALUE | **the add amount**, e.g. `A1 = +3` → `3` |
| SUM, SUBTRACT, STORE | omit the field |

The trap is ADD_VALUE. `SolutionStep._matches_value` compares against `node.value`, which for an Add Value node is its *offset*, not the number flowing through it. The verifier transcript prints the flowing value: `Connect A1 (3) → S1` on a node whose JSON says `"value": -4` means `from_value = -4`. Never copy the parenthesised number.

Omitting a field leaves it at `ConnectionStepData.ANY_VALUE` (`-2147483648`), which means "don't care". Do not write that sentinel literally — omit the line.

### 19.8 Deriving the phased wiring

A `SolutionPath` is an ordered sequence of **phases**. Each phase is the set of
wires that must be live at the moment one store latches, closed by a
`StoreValueStepData` recording which store latched and to what value. The
trailing phase has no terminator and holds the final configuration.

The hint system walks the phase the player is currently in, so a phase must
contain **every wire that must be live at its latch** — not just the wires newly
placed since the previous latch. The verifier's transcript is delta-style: it
stays silent about a wire that is already correct from an earlier phase. The
replay below reconstructs snapshots from those deltas, which is why it must be
run mechanically rather than read off the transcript by eye.

Capture the transcript once:

```
cd level_verifier
python3 verify.py <abs_path>/<level>.json --all --bound=<lo,hi> --max-latches <n> > /tmp/<level>.families.txt
```

Then, **per family, replay it mechanically.** Write a small script; do not read the steps and decide by eye.

```
state       : dict[(node_id, port_index)] -> (source_node_id, 0)
store_value : dict[store_id] -> int
```

Line handling:

| Transcript line | Action |
|---|---|
| `N. Connect X (v) → Y` | `state[(Y, 0)] = (X, 0)` |
| `N. Connect X (v) → Y top` | `state[(Y, 0)] = (X, 0)` |
| `N. Connect X (v) → Y bottom` | `state[(Y, 1)] = (X, 0)` |
| `[S latches k; its input auto-disconnects]` | emit a phase (below), then `store_value[S] = k`; `del state[(S, 0)]` |
| `[auto-severs A → B ...]` | no action — the overwrite already did it. Assert it agrees with what you replaced; a mismatch means you mis-parsed |

**On each latch line, before deleting the store's input**, emit a phase:

- `producer` = `state[(S, 0)]`, the node whose value is being captured.
- **Phase wiring** = the wires reachable by walking *backwards* through `state`
  from `producer` — every wire that transitively feeds it — plus the latch wire
  `producer → S` itself.
- **Phase terminator** = `(S, k)`.

The backward walk is not optional. A wire can be live at a latch while feeding
nothing that matters to it; carrying it into the phase would make the hint send
the player to build something the phase does not need. In `challenge_1` family 1,
`I1 → P1 top` and `I2 → P1 bottom` are live when `S1` latches and are correctly
kept, but by `S2`'s latch `P1` is fed from `M1` instead, and the walk drops the
stale pair.

At the end of the family, emit the **final phase**: the wires reachable by
walking *backwards* through `state` from every Output node, with no terminator.
**Prune it exactly as you prune a latch phase** — same backward walk, rooted at
the outputs instead of at a latch producer.

> Do not skip this prune on the grounds that minimality makes it unnecessary.
> Minimality guarantees every node is needed *somewhere in the solution*, which
> includes the latch phases. It does **not** guarantee every node is used in the
> *final configuration*. A node whose only job was to build a value into a store
> is idle at the end, but its input wire is still live — latching severs the
> store's own input, not wires elsewhere in the graph.
>
> `challenge_3` shows it: `A1` earns its place during the latch phases, and at
> the end `S1 → A1` is still live while `A1`'s output feeds nothing. Emitting it
> unpruned puts a connection in the final phase that contributes nothing to
> completing the level — the hint system would ask the player to build it, and
> challenge mode would withhold credit until they did.
>
> The arithmetic check in §19.13 will not catch this. `A1` is single-input and
> that input *is* wired, so nothing is partially wired and every Output still
> receives its target. The stale wire rides along silently. The backward walk is
> the only thing that removes it.

Drop any phase whose store is never read afterwards — neither as a source in a
later phase's wiring nor in the final phase. A latch nothing ever reads is dead
and must not be emitted.

Drop the whole family if it **keeps latching after the level could already have
been finished** — that is, if the store contents at some point part-way through
already make every output simultaneously reachable. Such a family latches a
value that was already sitting on a live node and then reads it straight back
out; every latch looks "used", so the dead-latch rule above will not catch it.
The solver now filters these at source (`_latches_past_the_finish`), so in
practice you will not see one; check it anyway if you are replaying a transcript
captured before that change.

Then **check your parse arithmetically, per phase**: evaluating a phase's wiring
must yield its terminator's value at `producer`, and evaluating the final phase
must give every Output node its declared target with no node left partially
wired. If it doesn't balance, your parse is wrong. Fix the parse. Do not adjust
the wiring to make it balance — that is hard rule 8.

#### Why snapshots and not "the steps since the last latch"

A wire made early can survive untouched across several latches. In
`levels/challenge.json`, family 1 sets `A1`'s input from `S2` at step 5, three
steps before `S1`'s final latch at step 6, and never rewires it. `A1` feeds both
of `P1`'s ports in the finished graph, so `O2` is unreachable without it — yet a
since-last-latch slice drops it entirely and the hint path becomes unsatisfiable.

The same trap applies to every intermediate phase, which is why each one is a
snapshot pruned by reachability rather than a slice of the transcript.

#### Worked replay — `challenge_1`, family 1

Transcript (15 steps, 2 latches) replays to three phases:

```
phase 0  (latch S1=9)      I1 → P1 top      I2 → P1 bottom
                           P1 → S1
phase 1  (latch S2=10)     I2 → M1 top      I1 → M1 bottom
                           M1 → P1 top      M1 → P1 bottom
                           P1 → S2
phase 2  (final)           S1 → P1 top      S2 → P1 bottom
                           S2 → M1 top      S1 → M1 bottom
                           M1 → O1          S2 → O2          P1 → O3
```

Arithmetic check: phase 0, `P1 = 2 + 7 = 9` ✓. Phase 1, `M1 = 7 − 2 = 5`,
`P1 = 5 + 5 = 10` ✓. Phase 2, `P1 = 9 + 10 = 19` → `O3`, `M1 = 10 − 9 = 1` →
`O1`, `S2 = 10` → `O2` ✓.

Note that phase 1 does **not** contain `I1 → P1 top` or `I2 → P1 bottom`: both
were overwritten by `M1` before `S2` latched. Note also that phase 2 contains
seven wires including ones placed long before the final latch.

### 19.9 Step order within a `SolutionPath`

`solution_steps` is a flat array. Phase structure is carried by position: a
`StoreValueStepData` **terminates** the phase it closes. Write each phase's
connections, then its latch connection, then its terminator; final phase last,
with no terminator.

```
[phase 0 connections…] [phase 0 latch connection] [phase 0 terminator]
[phase 1 connections…] [phase 1 latch connection] [phase 1 terminator]
…
[final phase connections…]
```

Two rules are load-bearing and checked in §19.13:

1. **The latch connection is last among its phase's connections**, immediately
   before the terminator, and its `to_type`/`to_slot` must be the STORE the
   terminator names. The hint system offers the first unsatisfied connection in
   the current phase; if the latch wire is offered early the player latches
   whatever garbage the producer currently holds.
2. **No terminator may be the first step of its phase** — a phase with no
   connections is malformed.

#### Ordering within a phase

The hint system treats a phase as a set, so order does not affect correctness.
It does affect the player: hints are offered in list order, so a badly ordered
phase asks the player to wire a node's output before that node has a value.

Order every phase by this single rule:

> **Walk the phase's target nodes in topological order — a node comes after
> every node that feeds it. On reaching a node, emit all of its input wires
> contiguously, ascending `to_port`.**

Two consequences worth stating separately, because both were previously
violated:

1. **A node's input wires always precede any wire leaving that node.** Wiring
   `M1 → P1` before `M1` has inputs shows the player a hint that produces
   nothing.
2. **A multi-input node's wires are contiguous.** Sum and Subtract take two
   today; the rule is written per-node rather than "two steps" so it still holds
   when node types with more inputs arrive.

Break ties among nodes that are simultaneously ready by `operations`-array
order, then `outputs`-array order — outputs are sinks and therefore always come
last. The latch connection is a sink too (its store has no outgoing wire in that
phase), so it lands last on its own; assert it anyway per rule 1 above.

Worked, for `challenge_1` phase 1 — targets `M1` (fed by inputs), `P1` (fed by
`M1`), `S2` (fed by `P1`), so the topological order is `M1`, `P1`, `S2`:

```
I2 → M1 top     I1 → M1 bottom      ; M1's inputs, contiguous
M1 → P1 top     M1 → P1 bottom      ; then P1's, now that M1 has a value
P1 → S2                             ; latch connection, sink, last
```

Within a phase the wiring is always a DAG — `GraphCanvas` blocks cycles — so a
topological order always exists.

This section is an inversion of the previous convention, which grouped all
`StoreValueStepData` at the head of the path and ordered connections by
`operations`-array position alone. Files in the old format are not readable
under the new one.

### 19.10 Reducing families to distinct paths

`verify.py --all` reports families that differ in *build order*. Families sharing
one **final configuration** remain the same path in game and must not be
duplicated — a duplicate makes path scoring ambiguous for no benefit.

Keying is unchanged, and is still on the final configuration only:

- `store_values`: sorted `(slot, value)` over stores read in the final phase
- `wires`: the final phase's set of `(from_type, from_slot, from_port, to_type, to_slot, to_port)`; **drop `to_port` from the key when `to_type` is SUM**, since it is commutative

Then quotient by permutations of same-type slots — a family that is another family with `S1` and `S2` exchanged is not a new path, because the hint system performs exactly that permutation search at runtime and will bind whichever assignment scores highest. Enumerate permutations per type, take the lexicographically smallest key.

What changes is **which representative you keep**. Phases are now authored, so
the journey is visible to the player as a hint sequence: keep the **shortest**
family in each equivalence class — fewest latch events first, then fewest
transcript steps — not the first in verifier order. This matches the
representative `notation.py` already selects when collapsing a family, and it is
the version a player is most likely to find unaided.

Order `solution_paths` shortest-first, as before.

Report the collapse explicitly: *"verify.py reported 4 families; 2 distinct final configurations."* A large collapse is worth mentioning — it may mean the level is less rich than `generator.solution_family_count` suggested, which is curation-relevant (§16).

**The §16a cap of 6 applies to the collapsed count**, since that is what becomes
`solution_paths` and therefore what challenge mode asks the player to work
through. In practice the two numbers agree — `notation.py` already groups
solutions by destination rather than journey, so `verify.py`'s family count is
usually the distinct-configuration count already, and this section's keying is a
safety net rather than a real reduction. A level where they differ substantially
is worth flagging to the designer either way.

**Completeness now matters more than it used to.** For hints, a missing path
degrades guidance. For challenge mode, a missing path means a player can find a
legitimate solution the game does not recognise and cannot be credited for. This
is why §16a rejects any level whose family search was not proven exhaustive, and
why `solution_paths` must list every distinct configuration rather than a
representative sample.

### 19.11 `.tres` text format

Rules, all confirmed against `challenge_1.tres`. These govern `.tres` syntax only
and are unaffected by the move to phased paths:

- Header: `[gd_resource type="Resource" script_class="LevelData" format=3]`. **Omit `uid=`** — Godot assigns one on first import. Never invent a UID. `load_steps` is optional; omit it.
- One `[ext_resource type="Script" uid="..." path="res://..." id="..."]` per distinct script actually used.
- `[sub_resource type="Resource" id="..."]` blocks must appear **before** anything referencing them. Order: step data → steps → paths → solution data.
- Each sub-resource carries `script = ExtResource("...")` first and `metadata/_custom_type_script = "uid://..."` last, with the same UID as its script.
- **Omit any exported property still at its default** (`from_slot = 0`, `to_port = 0`, `type = 0`, `value = 0` on a store). This is how Godot itself saves, and it keeps diffs readable.
- Typed arrays: `Array[ExtResource("id")]([SubResource("a"), SubResource("b")])`.
- Sub-resource ids are free-form strings. Use readable ones (`In0`, `Op2`, `SVD_p0_s0`, `Conn_p0_3`) rather than Godot's random suffixes — you are writing these by hand and will need to check them.
- `[resource]` block last, with `script`, the three arrays, `level_solution_data`, and the `metadata/_custom_type_script` line.

### 19.12 Worked example

`challenge_1`: `I1=2, I2=7; P1=+, M1=−, S1=s, S2=s; O1=1, O2=10, O3=19`. Family 1
of `verify.py --all`, replayed per §19.8 into three phases — `S1` latches 9,
then `S2` latches 10, then the final configuration gives `9+10=19`, `10−9=1`,
and `10` direct.

Slots: `P1`→SUM 0, `M1`→SUBTRACT 0, `S1`→STORE 0, `S2`→STORE 1; `I1`/`I2`→INPUT 0/1; `O1`/`O2`/`O3`→OUTPUT 0/1/2.

Both inputs appear here, in phases 0 and 1 — they are what the stores are loaded
from. They do **not** appear in the final phase, where the latched stores carry
everything. Under the previous final-wiring-only format this level emitted no
input connections at all; that is the most visible difference between the two
formats.

```
[gd_resource type="Resource" script_class="LevelData" format=3]

[ext_resource type="Script" uid="uid://bqkbdyhscmtcb" path="res://Levels/LevelData/graph_node_data.gd" id="GND"]
[ext_resource type="Script" uid="uid://ciy62d543op8" path="res://Levels/LevelData/level_data.gd" id="LD"]
[ext_resource type="Script" uid="uid://cexqyukx5s6ta" path="res://HintSystem/level_solution_data.gd" id="LSD"]
[ext_resource type="Script" uid="uid://cut5mll0elw0n" path="res://HintSystem/solution_path.gd" id="SP"]
[ext_resource type="Script" uid="uid://cltmh45jarwf8" path="res://HintSystem/solution_step.gd" id="SS"]
[ext_resource type="Script" uid="uid://b7d0piii6kegt" path="res://HintSystem/store_value_step_data.gd" id="SVD"]
[ext_resource type="Script" uid="uid://cxfcv878bwcua" path="res://HintSystem/connection_step_data.gd" id="CSD"]

; --- nodes: inputs I1, I2 ---
[sub_resource type="Resource" id="In0"]
script = ExtResource("GND")
value = 2
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

[sub_resource type="Resource" id="In1"]
script = ExtResource("GND")
value = 7
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

; --- nodes: operations P1, M1, S1, S2 ---
[sub_resource type="Resource" id="Op0"]
script = ExtResource("GND")
type = 3
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

[sub_resource type="Resource" id="Op1"]
script = ExtResource("GND")
type = 4
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

[sub_resource type="Resource" id="Op2"]
script = ExtResource("GND")
type = 5
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

[sub_resource type="Resource" id="Op3"]
script = ExtResource("GND")
type = 5
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

; --- nodes: outputs O1, O2, O3 ---
[sub_resource type="Resource" id="Out0"]
script = ExtResource("GND")
type = 1
value = 1
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

[sub_resource type="Resource" id="Out1"]
script = ExtResource("GND")
type = 1
value = 10
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

[sub_resource type="Resource" id="Out2"]
script = ExtResource("GND")
type = 1
value = 19
metadata/_custom_type_script = "uid://bqkbdyhscmtcb"

; ===== path 0, phase 0 — builds 9 into S1 =====
; I1 -> P1 top
[sub_resource type="Resource" id="D_p0_c0"]
script = ExtResource("CSD")
from_value = 2
to_type = 3
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c0"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c0")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; I2 -> P1 bottom
[sub_resource type="Resource" id="D_p0_c1"]
script = ExtResource("CSD")
from_slot = 1
from_value = 7
to_type = 3
to_port = 1
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c1"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c1")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; P1 -> S1  <- latch connection, last in phase
[sub_resource type="Resource" id="D_p0_c2"]
script = ExtResource("CSD")
from_type = 3
to_type = 5
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c2"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c2")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; terminator: S1 latches 9
[sub_resource type="Resource" id="D_p0_sv0"]
script = ExtResource("SVD")
value = 9
metadata/_custom_type_script = "uid://b7d0piii6kegt"

[sub_resource type="Resource" id="S_p0_sv0"]
script = ExtResource("SS")
step_data = SubResource("D_p0_sv0")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; ===== path 0, phase 1 — builds 10 into S2 =====
; topological order: M1's inputs, then P1's, then the latch
; I2 -> M1 top
[sub_resource type="Resource" id="D_p0_c3"]
script = ExtResource("CSD")
from_slot = 1
from_value = 7
to_type = 4
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c3"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c3")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; I1 -> M1 bottom
[sub_resource type="Resource" id="D_p0_c4"]
script = ExtResource("CSD")
from_value = 2
to_type = 4
to_port = 1
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c4"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c4")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; M1 -> P1 top
[sub_resource type="Resource" id="D_p0_c5"]
script = ExtResource("CSD")
from_type = 4
to_type = 3
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c5"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c5")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; M1 -> P1 bottom
[sub_resource type="Resource" id="D_p0_c6"]
script = ExtResource("CSD")
from_type = 4
to_type = 3
to_port = 1
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c6"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c6")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; P1 -> S2  <- latch connection, last in phase
[sub_resource type="Resource" id="D_p0_c7"]
script = ExtResource("CSD")
from_type = 3
to_type = 5
to_slot = 1
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c7"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c7")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; terminator: S2 latches 10
[sub_resource type="Resource" id="D_p0_sv1"]
script = ExtResource("SVD")
value = 10
slot = 1
metadata/_custom_type_script = "uid://b7d0piii6kegt"

[sub_resource type="Resource" id="S_p0_sv1"]
script = ExtResource("SS")
step_data = SubResource("D_p0_sv1")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; ===== path 0, phase 2 — final configuration, no terminator =====
; S1 -> P1 top
[sub_resource type="Resource" id="D_p0_c8"]
script = ExtResource("CSD")
from_type = 5
to_type = 3
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c8"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c8")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; S2 -> P1 bottom
[sub_resource type="Resource" id="D_p0_c9"]
script = ExtResource("CSD")
from_type = 5
from_slot = 1
to_type = 3
to_port = 1
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c9"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c9")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; S2 -> M1 top
[sub_resource type="Resource" id="D_p0_c10"]
script = ExtResource("CSD")
from_type = 5
from_slot = 1
to_type = 4
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c10"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c10")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; S1 -> M1 bottom
[sub_resource type="Resource" id="D_p0_c11"]
script = ExtResource("CSD")
from_type = 5
to_type = 4
to_port = 1
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c11"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c11")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; M1 -> O1 (= 1)
[sub_resource type="Resource" id="D_p0_c12"]
script = ExtResource("CSD")
from_type = 4
to_type = 1
to_value = 1
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c12"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c12")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; S2 -> O2 (= 10)
[sub_resource type="Resource" id="D_p0_c13"]
script = ExtResource("CSD")
from_type = 5
from_slot = 1
to_type = 1
to_slot = 1
to_value = 10
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c13"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c13")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

; P1 -> O3 (= 19)
[sub_resource type="Resource" id="D_p0_c14"]
script = ExtResource("CSD")
from_type = 3
to_type = 1
to_slot = 2
to_value = 19
metadata/_custom_type_script = "uid://cxfcv878bwcua"

[sub_resource type="Resource" id="S_p0_c14"]
script = ExtResource("SS")
step_data = SubResource("D_p0_c14")
metadata/_custom_type_script = "uid://cltmh45jarwf8"

[sub_resource type="Resource" id="Path0"]
script = ExtResource("SP")
solution_steps = Array[ExtResource("SS")]([SubResource("S_p0_c0"), SubResource("S_p0_c1"), SubResource("S_p0_c2"), SubResource("S_p0_sv0"), SubResource("S_p0_c3"), SubResource("S_p0_c4"), SubResource("S_p0_c5"), SubResource("S_p0_c6"), SubResource("S_p0_c7"), SubResource("S_p0_sv1"), SubResource("S_p0_c8"), SubResource("S_p0_c9"), SubResource("S_p0_c10"), SubResource("S_p0_c11"), SubResource("S_p0_c12"), SubResource("S_p0_c13"), SubResource("S_p0_c14")])
metadata/_custom_type_script = "uid://cut5mll0elw0n"

[sub_resource type="Resource" id="Solution"]
script = ExtResource("LSD")
solution_paths = Array[ExtResource("SP")]([SubResource("Path0")])
metadata/_custom_type_script = "uid://cexqyukx5s6ta"

[resource]
script = ExtResource("LD")
inputs = Array[ExtResource("GND")]([SubResource("In0"), SubResource("In1")])
operations = Array[ExtResource("GND")]([SubResource("Op0"), SubResource("Op1"), SubResource("Op2"), SubResource("Op3")])
outputs = Array[ExtResource("GND")]([SubResource("Out0"), SubResource("Out1"), SubResource("Out2")])
level_solution_data = SubResource("Solution")
metadata/_custom_type_script = "uid://ciy62d543op8"
```

The `;` comment lines are for this document's readability. Godot's parser tolerates them, but strip them from emitted files — the editor drops them on first save anyway, producing a spurious diff.

Add one more `Path<n>` block per distinct final configuration and list them all in `solution_paths`.

Note the shape of `solution_steps`: connections and terminators interleaved in
phase order, terminators at the *end* of their phase. A file with all its
`StoreValueStepData` at the head is in the old format and will not read
correctly.

Expect files roughly 2.5–3× the size of the old format on store levels — this
example goes from 9 steps to 17 for the same level. That is inherent to
authoring the journey rather than only the destination.

### 19.13 Verify before handing off

Run these as a script over each emitted `.tres`. This checks your *transcription*, not the level — the level's correctness was settled by the verifier and is not up for re-derivation.

1. **Round-trip.** Re-parse the `.tres`, rebuild the `(type, slot)` map from its own arrays, split each path into phases at its terminators, and reconstruct each phase's wiring. Assert it equals the phased wiring you extracted in §19.8, phase for phase.
2. **Arithmetic, per phase.** For each non-final phase, evaluate its wiring and assert the latch connection's source node holds the terminator's value. For the final phase, every Output node must receive its declared target; no node may be left partially wired.
3. **Referential integrity.** Every `(type, slot)` referenced by any step must exist in the arrays. Binding resolution `push_error`s and silently drops the type otherwise, which degrades hints without failing loudly.
3a. **Latch connection placement.** In every non-final phase, the last connection before the terminator must have `to_type = 5` (STORE) with `to_slot` equal to the terminator's `slot`. No other connection in that phase may target that store.
3b. **No empty phase.** Every terminator must be preceded by at least one connection within its own phase.
3c. **No dead latch.** Every terminator's store must appear as a `from_type = 5` source in some later phase, or in the final phase.
3d. **Distinct required states.** Compute each phase's required store state — for each store, the value of the last terminator on it, kept only if some phase from here on reads that store before re-latching it — and assert no two phases in one path produce identical maps. A collision means the hint system will silently skip a phase's work.
3e. **Topological ordering.** Within each phase, assert that no connection whose `from` node is a target of that phase appears before all of that node's own input connections, and that a multi-input node's input connections are contiguous. See §19.9.
4. **Engine limits.** `inputs.size() ≤ 4`, `operations.size() ≤ 6`, `outputs.size() ≤ 4`. Assert against `LevelBuilder`'s `INPUT_MAX` / `OPERATION_MAX` / `OUTPUT_MAX`, re-read from source rather than hardcoded here — these are expected to change.
5. **Display safety.** Every emitted `value` within its range per §9 — inputs −9..9, outputs −20..20, add amounts −9..9. Note these are three separate ranges, not two; the generator's flag defaults do not match them (§9).
6. **Structural diff.** Compare the shape of your file against the §19.12 example. Same block ordering, same defaults omitted, same `metadata/_custom_type_script` lines. Do not diff against an existing shipped `.tres` unless you have confirmed it is already in the phased format.

You cannot run Godot, so import is unverified. Say so, and ask the designer to open the project once and confirm the resources load without errors before building scenes on them.

### 19.14 What to report

Per emitted level: file path, tier, one-line "teaches", family count → distinct path count, phase count and the latch sequence per path (e.g. *"path 0: 3 phases, S1=9 → S2=10"*), and the seed/bound line from §18. Then the standing reminder that adding each resource to `LevelManager.level_data_list` remains manual (§19.1).

---

## 20. Known issues in the game project

Report these once per session if still present; do not fix them (hard rule 9, and they are outside your remit).

All three issues previously listed here — `level.gd` reading the wrong property,
`challenge_1.tscn` setting `solution_data` on the root node, and
`LevelBuilder.OPERATION_MAX` being 5 — have since been resolved. `level.gd` reads
`level_data.level_solution_data`, the per-level `.tscn` files have been replaced
by a single `Levels/level.tscn` driven by `LevelData`, and `OPERATION_MAX` is 6.

Re-check this section against the project rather than assuming it is current; if
you find nothing, report that and move on.

---

## 21. When things fail

- **Pipeline B produced nothing.** Remember it exits 0. Retry with `--exhaustive` first — that is the single most common cause. If it still returns nothing, report what was tried and which constraint appears binding.
- **Pipeline A exhausted resamples.** Try a different `--seed`, or a larger `--pool-inputs` / `--pool-ops`. If the targets themselves look unreachable, say so rather than raising the pool indefinitely.
- **A range rejection.** A clean one-liner means `--outputs` or `--input-values` fell outside its range; a traceback ending in *"outside the configured add-value range"* means an `add:N` did. Fix the value or widen the range deliberately — do not widen a range just to make a command pass.
- **`expected one argument` on a range or bound flag.** You used a space instead of `=` before a negative low value. See §9.
- **A Python traceback with any other message.** Malformed command. Fix the invocation; do not retry as-is and do not edit the source.
- **`minimal_within_bound` is null, or `solver_timeout_hit` is true.** Re-check that level manually via `verify.py` at its own recorded bound, or regenerate with a higher `--solve-timeout`. Do not ship it on the strength of its other fields.
- **Corpus calibration fails.** Stop entirely. Nothing generated in that session is trustworthy.
- **A `.tres` round-trip or arithmetic check fails (§19.13).** Your transcription is wrong, not the level. Re-run the replay in §19.8 from the captured transcript. Do not adjust wires until the numbers work — that is exactly the failure mode hard rule 8 exists to catch.
- **A transcript line doesn't match any pattern in §19.8.** Stop and report the literal line. The verifier's rendering has changed and the replay parser is now unsafe; do not guess at the new format.
- **Tools error or hang beyond the documented performance envelope.** Report the invocation and the failure. Do not debug, patch around, or fall back to hand-verification.
- **A result surprises you.** Say so explicitly and keep the tool's answer. A surprising-but-verified level is often the most interesting one in the batch — and a surprise is also the first sign of a gap the designer needs to hear about.
