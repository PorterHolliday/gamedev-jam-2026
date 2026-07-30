#!/usr/bin/env python3
"""
Standalone level generator CLI for the node-puzzle game.

Inverts the level_verifier's solve() into a generator: two pipelines produce
new levels using the verifier as a pure correctness oracle. See README.md in
this directory for design decisions (ranking formula, isomorphism filter,
file naming) and for the honest-incompleteness contract every emitted level
file follows.

Usage:
    python3 generate.py deletion --outputs 1,17,19 --pool-inputs 4 --pool-ops 6 --seed 42
    python3 generate.py enumerate --inputs 2 --ops "sum,subtract,store,store" --targets 3
    python3 generate.py enumerate --inputs 2 --ops "sum,subtract,store,store" --targets 3 --exhaustive

level_verifier/ is treated as a frozen dependency: this file only imports
from it (via level_verifier/api.py) and never modifies its logic.
"""
from __future__ import annotations

import argparse
import itertools
import json
import os
import random
import signal
import sys
from collections import Counter
from typing import Dict, List, Optional, Tuple

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "level_verifier"))

from api import (  # noqa: E402
    Level, OpSpec,
    solve, Solution, SearchResult,
    render_solution, dedupe_families,
    minimality_report,
)

# NOTE on bound/timeout defaults: solve()'s own default bound is (-200, 200),
# documented as "generous enough for anything hand-designed that fits the
# size constraints." That assumption doesn't hold for RANDOMLY sampled pools:
# reach.py's reach_values() is an unmemoized-in-practice DFS over networks
# (its cache key includes the accumulated value pool, which rarely repeats),
# so a handful of sum/subtract ops on a wide bound can blow up combinatorially
# trying to prove an unsolvable candidate has no witness -- confirmed directly
# (a random 4-input/6-op pool took >20s at bound (-200,200), still 4.9s at
# (-25,25), and only became fast, ~1-2s, at (-20,20)-ish bounds). This is a
# real characteristic of the frozen verifier, not something the generator can
# fix by changing solve()/reach.py. Two independent mitigations, both applied
# by default and both overridable:
#   1. A tighter default bound for generation than the verifier's own default.
#   2. A wall-clock timeout per solve() call (see solve_with_timeout below) --
#      an additional, generator-owned incompleteness budget layered on top of
#      (bound, max_latches). A timeout is treated exactly like "couldn't prove
#      it," never as a positive or negative answer, and is recorded honestly
#      in emitted metadata alongside the SearchResult.exhausted flags.
DEFAULT_BOUND: Tuple[int, int] = (-20, 20)
DEFAULT_MAX_LATCHES = 8
DEFAULT_SOLVE_TIMEOUT = 8  # seconds, per solve() call; see note above
VALUE_RANGE = range(-20, 21)          # design constraint: values live in -20..20
OP_TYPES = ["add", "sum", "subtract", "store"]
OP_PREFIX = {"add": "A", "sum": "P", "subtract": "M", "store": "S"}
# Empirically measured (not just theoretical): 4 combinational ops in the
# SAME level as 1-2 store ops pushed a single find_all=False solve() call
# from ~1-2s to >20s, even though the number of BFS states explored barely
# changed -- the cost is in re-deriving reach_values() per newly-discovered
# store state (its cache is keyed by exact source-value set, which differs
# per state almost every time). 3 combinational ops kept every measured case
# under 2s. This cap trades a slightly smaller combinational-op search space
# for keeping every solve() call inside the frozen verifier fast.
DEFAULT_MAX_COMBINATIONAL_OPS = 3


class SolveTimeout(Exception):
    pass


def _alarm_handler(signum, frame):
    raise SolveTimeout()


def call_with_timeout(fn, *args, timeout=DEFAULT_SOLVE_TIMEOUT, **kwargs):
    """Runs fn(*args, **kwargs) under a wall-clock timeout; returns None
    instead of raising or hanging if it doesn't finish in time. Used to wrap
    ANY verifier call that ultimately bottoms out in solve() -- not just
    solve() itself, but also minimality_report() (which calls solve() once
    per deletable node) -- since the same reach_values() blowup risk applies
    regardless of which verifier entry point triggers it. Unix-only
    (SIGALRM); fine on this generator's Linux sandbox."""
    if timeout is None or timeout <= 0:
        return fn(*args, **kwargs)
    old_handler = signal.signal(signal.SIGALRM, _alarm_handler)
    signal.alarm(timeout)
    try:
        return fn(*args, **kwargs)
    except SolveTimeout:
        return None
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)


def solve_with_timeout(level: Level, bound, max_latches, find_all=False, max_families=10,
                        timeout=DEFAULT_SOLVE_TIMEOUT) -> Optional[SearchResult]:
    """Same contract as solve(), except it returns None instead of raising or
    hanging if the call doesn't finish within `timeout` wall-clock seconds.
    None must be treated as a THIRD outcome, distinct from solvable=True and
    solvable=False -- it means our own generation run didn't have the patience
    to find out, not that the verifier proved anything."""
    return call_with_timeout(solve, level, bound=bound, max_latches=max_latches,
                              find_all=find_all, max_families=max_families, timeout=timeout)


# --------------------------------------------------------------------------
# id / construction helpers
# --------------------------------------------------------------------------

def make_input_ids(n: int) -> List[str]:
    return [f"I{i + 1}" for i in range(n)]


def make_output_dict(values: List[int]) -> Dict[str, int]:
    return {f"O{i + 1}": v for i, v in enumerate(values)}


class IdCounters:
    """Assigns sequential, type-prefixed ids (A1, A2, P1, M1, S1, S2, ...)."""

    def __init__(self):
        self.counts = {t: 0 for t in OP_TYPES}

    def next(self, op_type: str) -> str:
        self.counts[op_type] += 1
        return f"{OP_PREFIX[op_type]}{self.counts[op_type]}"


def random_distinct_values(rng: random.Random, n: int, low=-20, high=20,
                            exclude=()) -> List[int]:
    pool = [v for v in range(low, high + 1) if v not in exclude]
    rng.shuffle(pool)
    if len(pool) < n:
        raise ValueError(f"Not enough distinct values in [{low},{high}] to pick {n}")
    return pool[:n]


def random_op_pool(rng: random.Random, n: int, allowed_types=OP_TYPES,
                    add_value_range=(-20, 20),
                    max_combinational=DEFAULT_MAX_COMBINATIONAL_OPS) -> Dict[str, OpSpec]:
    """Samples a pool of n ops. Combinational ops (add/sum/subtract) are
    capped at `max_combinational` -- reach_values()'s DFS over combinational
    networks grows combinatorially with op count (see module-level note on
    DEFAULT_BOUND), so an uncapped draw risks pathologically slow solve()
    calls purely from having drawn e.g. 6 sum/subtract ops. Any op count
    beyond the cap is forced to 'store' (or, if 'store' isn't in
    allowed_types, simply not drawn -- n may come out smaller than requested)."""
    counters = IdCounters()
    ops: Dict[str, OpSpec] = {}
    combinational_types = [t for t in allowed_types if t != "store"]
    store_allowed = "store" in allowed_types
    comb_count = 0
    for _ in range(n):
        can_use_combinational = combinational_types and comb_count < max_combinational
        if can_use_combinational and store_allowed:
            t = rng.choice(allowed_types)
        elif can_use_combinational:
            t = rng.choice(combinational_types)
        elif store_allowed:
            t = "store"
        else:
            break  # no combinational budget left and store isn't allowed -- stop early
        if t != "store":
            comb_count += 1
        oid = counters.next(t)
        val = rng.randint(*add_value_range) if t == "add" else None
        ops[oid] = OpSpec(oid, t, val)
    return ops


def parse_int_list(s: str) -> List[int]:
    return [int(x) for x in s.split(",") if x.strip() != ""]


def parse_bound(s: str) -> Tuple[int, int]:
    lo, hi = s.split(",")
    return (int(lo), int(hi))


def parse_op_type_list(s: str) -> List[Tuple[str, Optional[int]]]:
    """'add:5,sum,subtract,store,store' -> [('add',5), ('sum',None), ...]
    in the given order (order determines P1/M1/S1/S2/... assignment)."""
    specs = []
    for tok in s.split(","):
        tok = tok.strip()
        if not tok:
            continue
        if ":" in tok:
            t, v = tok.split(":")
            specs.append((t.strip(), int(v)))
        else:
            specs.append((tok, None))
    return specs


def build_fixed_ops(spec_list: List[Tuple[str, Optional[int]]],
                     rng: Optional[random.Random] = None,
                     add_value_range=(-20, 20)) -> Dict[str, OpSpec]:
    counters = IdCounters()
    ops: Dict[str, OpSpec] = {}
    for t, v in spec_list:
        if t not in OP_TYPES:
            raise ValueError(f"Unknown op type '{t}' (expected one of {OP_TYPES})")
        oid = counters.next(t)
        if t == "add":
            val = v if v is not None else (rng.randint(*add_value_range) if rng else 0)
        else:
            val = None
        ops[oid] = OpSpec(oid, t, val)
    return ops


def level_to_dict(level: Level) -> dict:
    ops = {}
    for oid, spec in level.operations.items():
        if spec.type == "add":
            ops[oid] = {"type": "add", "value": spec.value}
        else:
            ops[oid] = {"type": spec.type}
    return {
        "name": level.name,
        "inputs": dict(level.inputs),
        "operations": ops,
        "outputs": dict(level.outputs),
    }


def has_trivial_output(level: Level) -> bool:
    """An output target equal to an input value is satisfied by a single
    direct wire -- not a puzzle. Both pipelines' post-filter step discards
    these (spec section 9, 'Post-filters')."""
    return bool(set(level.inputs.values()) & set(level.outputs.values()))


# --------------------------------------------------------------------------
# honest-incompleteness bookkeeping
# --------------------------------------------------------------------------

class Verdict:
    """Uniform result shape for a budgeted solvability check: solve()'s own
    SearchResult has (solvable, exhausted); this adds a third, distinct
    outcome -- timed_out -- for when our own wall-clock patience (not the
    verifier's bound/max_latches) ran out first. timed_out implies
    solvable=False, exhausted=False: a timeout is never treated as a proof of
    anything, positive or negative."""
    __slots__ = ("solvable", "exhausted", "timed_out")

    def __init__(self, solvable: bool, exhausted: bool, timed_out: bool = False):
        self.solvable = solvable
        self.exhausted = exhausted
        self.timed_out = timed_out


class SolveBudget:
    """Bundles the (bound, max_latches, wall-clock timeout) a generation run
    commits to, so every solvability/minimality claim can be traced back to
    the search budget it was checked under. Every emitted level file records
    these values -- 'minimal by construction' always means minimal relative
    to this budget, never unconditionally (spec section 9, 'Generated levels
    inherit the solver's bounds'). `any_timeout` is a sticky flag: True if any
    solvable() call under this budget ever hit the wall-clock timeout, so a
    caller can propagate that into a level's metadata even after the fact."""

    def __init__(self, bound: Tuple[int, int] = DEFAULT_BOUND,
                 max_latches: int = DEFAULT_MAX_LATCHES,
                 timeout: Optional[int] = DEFAULT_SOLVE_TIMEOUT):
        self.bound = bound
        self.max_latches = max_latches
        self.timeout = timeout
        self.any_timeout = False

    def solvable(self, level: Level) -> Verdict:
        r = solve_with_timeout(level, self.bound, self.max_latches, find_all=False,
                                timeout=self.timeout)
        if r is None:
            self.any_timeout = True
            return Verdict(False, False, timed_out=True)
        return Verdict(r.solvable, r.exhausted)


# --------------------------------------------------------------------------
# Pipeline A -- delta-debugging shrink (spec section 9)
# --------------------------------------------------------------------------

def generate_by_deletion(outputs: Dict[str, int], pool_inputs: int, pool_ops: int,
                          seed: int, budget: SolveBudget,
                          allowed_op_types=OP_TYPES, add_value_range=(-20, 20),
                          max_resamples=200, name="generated") -> Optional[dict]:
    """Start over-provisioned, delete greedily, keep whatever breaks when
    removed. Minimal by construction: one pass, no fixpoint loop needed,
    since solvability is monotone in the node set (see module docstring)."""
    rng = random.Random(seed)

    for attempt in range(max_resamples):
        input_ids = make_input_ids(pool_inputs)
        input_values = random_distinct_values(rng, pool_inputs)
        inputs = dict(zip(input_ids, input_values))
        ops = random_op_pool(rng, pool_ops, allowed_types=allowed_op_types,
                              add_value_range=add_value_range)

        level = Level(name=name, inputs=inputs, operations=ops, outputs=dict(outputs))
        result = budget.solvable(level)
        if not result.solvable:
            continue  # cannot shrink into solvability -- resample, don't repair

        deletable = level.all_deletable_nodes()
        rng.shuffle(deletable)  # order-dependent by design -- reshuffling yields
                                 # different minimal levels from the same pool
        deletion_exhausted = [result.exhausted]
        for node_id in deletable:
            if node_id not in level.inputs and node_id not in level.operations:
                continue  # defensive: ids are unique, this shouldn't trigger
            candidate = level.without_node(node_id)
            cand_result = budget.solvable(candidate)
            deletion_exhausted.append(cand_result.exhausted)
            if cand_result.solvable:
                level = candidate  # deletion survives permanently

        return {
            "level": level,
            "seed": seed,
            "attempt": attempt,
            "deletion_pass_exhausted": all(deletion_exhausted),
        }

    return None  # resample budget exhausted without finding a solvable starting pool


# --------------------------------------------------------------------------
# Pipeline B -- forward enumeration with derived targets (spec section 9)
# --------------------------------------------------------------------------

def probe_reachable(inputs: Dict[str, int], ops: Dict[str, OpSpec], value: int,
                     budget: SolveBudget) -> Tuple[bool, bool]:
    """Is `value` reachable at all from (inputs, ops), accounting for store
    ratcheting across multiple latches? reach.py's reach_values() is single-
    phase only and can't answer this when ops includes stores, so this reuses
    solve() itself via a synthetic one-output probe level (see project notes)."""
    probe = Level(name="_probe", inputs=inputs, operations=ops, outputs={"_probe": value})
    r = solve_with_timeout(probe, budget.bound, budget.max_latches, find_all=False,
                            timeout=budget.timeout)
    if r is None:
        budget.any_timeout = True
        return False, False  # unknown treated as "not reachable, not proven" -- never a positive
    return r.solvable, r.exhausted


def reach_all(inputs: Dict[str, int], ops: Dict[str, OpSpec], budget: SolveBudget,
              candidate_range=VALUE_RANGE) -> Tuple[set, bool]:
    reachable = set()
    all_exhausted = True
    for v in candidate_range:
        ok, exhausted = probe_reachable(inputs, ops, v, budget)
        if ok:
            reachable.add(v)
        all_exhausted = all_exhausted and exhausted
    return reachable, all_exhausted


def without(inputs: Dict[str, int], ops: Dict[str, OpSpec], node_id: str):
    if node_id in inputs:
        return ({k: v for k, v in inputs.items() if k != node_id}, dict(ops))
    elif node_id in ops:
        return (dict(inputs), {k: v for k, v in ops.items() if k != node_id})
    raise KeyError(node_id)


def generate_by_enumeration(inputs: Dict[str, int], ops: Dict[str, OpSpec],
                             budget: SolveBudget, exhaustive=False, max_targets=4,
                             max_emit: Optional[int] = None, name_prefix="generated",
                             candidate_range=VALUE_RANGE) -> Tuple[List[dict], bool]:
    """Returns (survivors, setup_exhausted). Each survivor is
    {'level', 'is_minimal', 'rows'}. setup_exhausted reports whether every
    reach_all() call underneath this run proved its result within budget."""
    all_nodes = list(inputs.keys()) + list(ops.keys())
    R_full, r_full_exh = reach_all(inputs, ops, budget, candidate_range)

    D: Dict[str, set] = {}
    setup_exhausted = r_full_exh
    for n in all_nodes:
        sub_inputs, sub_ops = without(inputs, ops, n)
        R_N, r_n_exh = reach_all(sub_inputs, sub_ops, budget, candidate_range)
        setup_exhausted = setup_exhausted and r_n_exh
        D[n] = R_full - R_N

    if not exhaustive:
        design_vals = set(candidate_range)
        for n, d in D.items():
            if not (d & design_vals):
                return [], setup_exhausted  # N can never be forced -- discard this pairing

    design_range = [v for v in sorted(R_full) if -20 <= v <= 20]

    iso = IsomorphismFilter()
    results: List[dict] = []
    for k in range(1, max_targets + 1):
        for combo in itertools.combinations(design_range, k):
            combo_set = set(combo)
            if not exhaustive:
                if not all((not d) or (d & combo_set) for d in D.values()):
                    continue  # doesn't cover every forcing difference set
            outputs = make_output_dict(list(combo))
            level = Level(name=name_prefix, inputs=dict(inputs), operations=dict(ops),
                          outputs=outputs)
            if has_trivial_output(level):
                continue
            check = budget.solvable(level)
            if not check.solvable:
                continue
            # Covering is sufficient for minimality in theory (spec section 9),
            # but a level can also be forced by simultaneity rather than
            # reachability -- run the real leave-one-out anyway. It's cheap
            # insurance on the small set of levels that get this far, and it
            # is how --exhaustive levels get judged in the first place.
            mr = call_with_timeout(minimality_report, level, budget.bound, budget.max_latches,
                                    timeout=budget.timeout)
            if mr is None:
                budget.any_timeout = True
                if exhaustive:
                    continue  # can't confirm minimality within budget -- skip, don't assert
                is_minimal, rows = None, []
            else:
                is_minimal, rows = mr
                if exhaustive and not is_minimal:
                    continue
            if not iso.is_new(level):
                continue
            results.append({"level": level, "is_minimal": is_minimal, "rows": rows})
            if max_emit and len(results) >= max_emit:
                return results, setup_exhausted
    return results, setup_exhausted


# --------------------------------------------------------------------------
# isomorphism post-filter (no counterpart in level_verifier -- written fresh)
# --------------------------------------------------------------------------

def canonical_signature(level: Level) -> tuple:
    """Canonicalize a level's operation multiset by (type, value), the same
    way notation._symmetry_classes groups functionally-interchangeable nodes
    within one level's solution space -- extended here to compare two
    DIFFERENT levels for structural equivalence under node relabeling.
    Two levels are isomorphic iff: same input value set, same output target
    set, and the same (type, value) op multiset (any two sum/subtract/store
    nodes are interchangeable; two add nodes are interchangeable only if they
    share the same value)."""
    op_counts = Counter((spec.type, spec.value) for spec in level.operations.values())
    return (
        frozenset(level.inputs.values()),
        frozenset(level.outputs.values()),
        tuple(sorted(op_counts.items(), key=lambda kv: (kv[0][0], kv[0][1] or 0))),
    )


class IsomorphismFilter:
    def __init__(self):
        self.seen = set()

    def is_new(self, level: Level) -> bool:
        sig = canonical_signature(level)
        if sig in self.seen:
            return False
        self.seen.add(sig)
        return True


# --------------------------------------------------------------------------
# ranking / tier assignment
# --------------------------------------------------------------------------

def analyze_level(level: Level, budget: SolveBudget, max_families=10,
                   timeout_multiplier=3) -> Optional[dict]:
    """Runs the expensive find_all=True search -- only call on survivors
    that already passed the cheap find_all=False filters, never in a hot
    search loop (up to ~15s per call per project notes, so this gets a longer
    timeout budget than plain solvability checks). If even that times out,
    falls back to the single witness a cheap find_all=False call can still
    provide, and records family_count as None ("unknown, search timed out")
    rather than silently reporting 1 -- see honest-incompleteness note."""
    timeout = (budget.timeout * timeout_multiplier) if budget.timeout else None
    result = call_with_timeout(solve, level, bound=budget.bound, max_latches=budget.max_latches,
                                find_all=True, max_families=max_families, timeout=timeout)
    if result is None:
        budget.any_timeout = True
        fallback = solve_with_timeout(level, budget.bound, budget.max_latches,
                                       find_all=False, timeout=budget.timeout)
        if fallback is None or not fallback.solvable:
            return None
        families = dedupe_families(level, fallback.solutions)
        best = families[0]
        steps = render_solution(level, best)
        return {
            "solution_length": len(steps),
            "latch_count": best.latch_count,
            "family_count": None,
            "families_exhausted": False,
        }
    if not result.solvable:
        return None
    families = dedupe_families(level, result.solutions)
    best = families[0]
    steps = render_solution(level, best)
    return {
        "solution_length": len(steps),
        "latch_count": best.latch_count,
        "family_count": len(families),
        "families_exhausted": result.exhausted,
    }


def score_level(analysis: dict, richer_families_are_harder=False) -> float:
    """Difficulty score: longer solutions and more latches raise it; by
    default, more distinct solution families LOWER it (more ways to solve a
    level tends to make it more forgiving to a player). The spec explicitly
    leaves this a design call and asks it be a flag rather than a hard-coded
    preference -- --richer-families-are-harder flips the sign. An unknown
    family_count (timed-out family search) contributes 0 -- neutral, not a
    guess in either direction."""
    family_count = analysis["family_count"]
    fam_term = 0 if family_count is None else (family_count - 1)
    if not richer_families_are_harder:
        fam_term = -fam_term
    return analysis["solution_length"] + 2 * analysis["latch_count"] + fam_term


# Tier boundaries are an arbitrary, documented default (see README) -- tune
# to taste, nothing upstream constrains this choice.
TIER_THRESHOLDS = [4, 8, 12, 17]


def assign_tier(score: float) -> int:
    for i, t in enumerate(TIER_THRESHOLDS, start=1):
        if score <= t:
            return i
    return len(TIER_THRESHOLDS) + 1


# --------------------------------------------------------------------------
# emitting level files
# --------------------------------------------------------------------------

def emit_level(level: Level, out_dir: str, pipeline: str, seed, budget: SolveBudget,
               minimal_info: Tuple[bool, list], analysis: Optional[dict],
               tier: Optional[int], extra: Optional[dict] = None) -> str:
    is_minimal, rows = minimal_info
    data = level_to_dict(level)
    data["generator"] = {
        "pipeline": pipeline,
        "seed": seed,
        "bound": list(budget.bound),
        "max_latches": budget.max_latches,
        "minimal_within_bound": is_minimal,
        "minimality_rows_exhausted": all(r[2] for r in rows) if rows else None,
        "solution_length": analysis["solution_length"] if analysis else None,
        "latch_count": analysis["latch_count"] if analysis else None,
        "solution_family_count": analysis["family_count"] if analysis else None,
        "family_search_exhausted": analysis["families_exhausted"] if analysis else None,
        "tier": tier,
    }
    if extra:
        data["generator"].update(extra)

    os.makedirs(out_dir, exist_ok=True)
    base = level.name
    fname = f"{base}.json"
    path = os.path.join(out_dir, fname)
    i = 2
    while os.path.exists(path):
        fname = f"{base}_{i}.json"
        path = os.path.join(out_dir, fname)
        i += 1
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    return path


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def cmd_deletion(args):
    outputs = make_output_dict(parse_int_list(args.outputs))
    budget = SolveBudget(parse_bound(args.bound) if args.bound else DEFAULT_BOUND,
                          args.max_latches, timeout=args.solve_timeout)
    allowed = args.op_types.split(",") if args.op_types else OP_TYPES

    result = generate_by_deletion(outputs, args.pool_inputs, args.pool_ops, args.seed,
                                   budget, allowed_op_types=allowed, name=args.name)
    if result is None:
        print("Failed to find a solvable starting pool after max resamples; "
              "try a different --seed or larger --pool-inputs/--pool-ops.",
              file=sys.stderr)
        sys.exit(1)

    level = result["level"]
    if has_trivial_output(level):
        print("Note: generated level has a trivial output (equals an input value) "
              "-- consider a different seed.", file=sys.stderr)

    mr = call_with_timeout(minimality_report, level, budget.bound, budget.max_latches,
                            timeout=budget.timeout)
    if mr is None:
        budget.any_timeout = True
        is_minimal, rows = None, []
        print("Note: final minimality sanity-check timed out; deletion-loop bookkeeping "
              "still claims this level is minimal within budget, but that claim is now "
              "unconfirmed by an independent check.", file=sys.stderr)
    else:
        is_minimal, rows = mr
    analysis = analyze_level(level, budget, max_families=args.max_families)
    score = score_level(analysis, args.richer_families_are_harder) if analysis else None
    tier = assign_tier(score) if score is not None else None

    path = emit_level(level, args.out_dir, "deletion", args.seed, budget,
                       (is_minimal, rows), analysis, tier,
                       extra={"resample_attempt": result["attempt"],
                              "deletion_pass_exhausted": result["deletion_pass_exhausted"],
                              "solver_timeout_hit": budget.any_timeout})
    print(f"Wrote {path}")
    print(f"  inputs={dict(level.inputs)}")
    print(f"  operations={[(oid, s.type, s.value) for oid, s in level.operations.items()]}")
    print(f"  outputs={dict(level.outputs)}")
    print(f"  minimal_within_bound={is_minimal}  tier={tier}")


def cmd_enumerate(args):
    input_ids = make_input_ids(args.inputs)
    if args.input_values:
        given = parse_int_list(args.input_values)
        if len(given) != args.inputs:
            raise SystemExit("--input-values count must match --inputs")
        input_values = given
    else:
        rng = random.Random(args.seed)
        input_values = random_distinct_values(rng, args.inputs)
    inputs = dict(zip(input_ids, input_values))

    spec_list = parse_op_type_list(args.ops)
    ops = build_fixed_ops(spec_list, rng=random.Random(args.seed))

    budget = SolveBudget(parse_bound(args.bound) if args.bound else DEFAULT_BOUND,
                          args.max_latches, timeout=args.solve_timeout)

    survivors, setup_exhausted = generate_by_enumeration(
        inputs, ops, budget, exhaustive=args.exhaustive, max_targets=args.targets,
        max_emit=args.max_emit, name_prefix=args.name)

    if not survivors:
        print("No levels survived enumeration for this (inputs, ops) pairing "
              "-- either nothing was solvable, or (in fast-path mode) some "
              "node could never be forced within the design range.",
              file=sys.stderr)
        return

    ranked = []
    for s in survivors:
        level = s["level"]
        analysis = analyze_level(level, budget, max_families=args.max_families)
        if analysis is None:
            continue
        score = score_level(analysis, args.richer_families_are_harder)
        ranked.append((score, level, s, analysis))
    ranked.sort(key=lambda r: r[0])

    for idx, (score, level, s, analysis) in enumerate(ranked):
        level.name = f"{args.name}_{idx + 1}"
        tier = assign_tier(score)
        path = emit_level(level, args.out_dir, "enumerate", args.seed, budget,
                           (s["is_minimal"], s["rows"]), analysis, tier,
                           extra={"exhaustive": args.exhaustive,
                                  "reach_setup_exhausted": setup_exhausted,
                                  "solver_timeout_hit": budget.any_timeout})
        print(f"Wrote {path}  tier={tier} score={score:.1f} outputs={dict(level.outputs)}")


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="generate.py",
        description="Generate node-puzzle levels using level_verifier as a correctness oracle.")
    sub = p.add_subparsers(dest="command", required=True)

    pa = sub.add_parser("deletion", help="Pipeline A: delta-debugging shrink to a minimal level.")
    pa.add_argument("--outputs", required=True,
                     help="Comma-separated output target values, e.g. 1,17,19")
    pa.add_argument("--pool-inputs", type=int, default=4)
    pa.add_argument("--pool-ops", type=int, default=6)
    pa.add_argument("--op-types", default=None,
                     help="Comma-separated allowed op types to sample from "
                          "(default: add,sum,subtract,store)")
    pa.add_argument("--seed", type=int, default=0)
    pa.add_argument("--bound", default=None,
                     help=f"lo,hi (default {DEFAULT_BOUND[0]},{DEFAULT_BOUND[1]} -- deliberately "
                          "tighter than the verifier's own -200,200 default; see module docstring)")
    pa.add_argument("--max-latches", type=int, default=DEFAULT_MAX_LATCHES)
    pa.add_argument("--max-families", type=int, default=10)
    pa.add_argument("--solve-timeout", type=int, default=DEFAULT_SOLVE_TIMEOUT,
                     help="Wall-clock seconds per solve() call before giving up on it "
                          "(0 disables the timeout)")
    pa.add_argument("--richer-families-are-harder", action="store_true")
    pa.add_argument("--name", default="generated")
    pa.add_argument("--out-dir", default="levels")
    pa.set_defaults(func=cmd_deletion)

    pb = sub.add_parser("enumerate", help="Pipeline B: forward enumeration with derived targets.")
    pb.add_argument("--inputs", type=int, required=True, help="Number of inputs")
    pb.add_argument("--input-values", default=None,
                     help="Comma-separated explicit input values (else random distinct)")
    pb.add_argument("--ops", required=True,
                     help='Comma-separated op types in id-assignment order, '
                          'e.g. "sum,subtract,store,store" (add ops: "add:5")')
    pb.add_argument("--targets", type=int, default=4,
                     help="Max output tuple size to try, sweeping 1..this (default 4)")
    pb.add_argument("--exhaustive", action="store_true",
                     help="Skip the covering fast path; run full leave-one-out on "
                          "every candidate target tuple")
    pb.add_argument("--seed", type=int, default=0)
    pb.add_argument("--bound", default=None,
                     help=f"lo,hi (default {DEFAULT_BOUND[0]},{DEFAULT_BOUND[1]})")
    pb.add_argument("--max-latches", type=int, default=DEFAULT_MAX_LATCHES)
    pb.add_argument("--max-families", type=int, default=10)
    pb.add_argument("--solve-timeout", type=int, default=DEFAULT_SOLVE_TIMEOUT,
                     help="Wall-clock seconds per solve() call before giving up on it "
                          "(0 disables the timeout)")
    pb.add_argument("--max-emit", type=int, default=20,
                     help="Stop after this many surviving levels (safety valve on "
                          "the up-to-~100k tuple search)")
    pb.add_argument("--richer-families-are-harder", action="store_true")
    pb.add_argument("--name", default="generated")
    pb.add_argument("--out-dir", default="levels")
    pb.set_defaults(func=cmd_enumerate)

    return p


def main():
    parser = build_arg_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
