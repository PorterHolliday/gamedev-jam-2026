"""
Outer search over store contents (the only durable state between phases).
"""
from __future__ import annotations
import itertools
from dataclasses import dataclass, field
from typing import Dict, List, Tuple

from reach import PlacedNode, reach_values, find_covering_networks, prune_to_needed
from model import Level


@dataclass(frozen=True)
class StoreState:
    values: tuple  # aligned with store_ids; None = empty


@dataclass
class LatchPhase:
    store_id: str
    value: int
    built: List[PlacedNode]
    assignment: Dict[str, str]   # {'_latch': producer_node_id}


@dataclass
class FinalPhase:
    built: List[PlacedNode]
    assignment: Dict[str, str]   # output_id -> producer_node_id


@dataclass
class Solution:
    latches: List[LatchPhase]
    final: FinalPhase
    latch_count: int


@dataclass
class SearchResult:
    solvable: bool
    bound: Tuple[int, int]
    max_latches: int
    exhausted: bool           # True if the full state space (within bound) was explored
    solutions: List[Solution] = field(default_factory=list)
    states_explored: int = 0


def sources_for_state(level: Level, state: StoreState, store_ids: List[str]) -> List[PlacedNode]:
    src = [PlacedNode(iid, v, "source") for iid, v in level.inputs.items()]
    for sid, val in zip(store_ids, state.values):
        if val is not None:
            src.append(PlacedNode(sid, val, "source"))
    return src


def _check_goal(level, state, store_ids, comb_ops, bound, cache, reach_fn=None):
    if state in cache:
        return cache[state]
    srcs = sources_for_state(level, state, store_ids)
    # Cheap necessary-condition prune: every target must be individually
    # reachable before we pay for the expensive simultaneous-coverage search.
    if reach_fn is not None:
        quick = reach_fn(frozenset(n.value for n in srcs))
        if not set(level.outputs.values()).issubset(quick):
            cache[state] = None
            return None
    res = find_covering_networks(srcs, comb_ops, bound, level.outputs, max_witnesses=1)
    cache[state] = res[0] if res else None
    return cache[state]


def solve(level: Level, bound: Tuple[int, int] = (-200, 200), max_latches: int = 12,
          find_all: bool = False, max_families: int = 10) -> SearchResult:
    store_ids = sorted(level.store_ops().keys())
    comb_ops = level.combinational_ops()

    start = StoreState(tuple(None for _ in store_ids))
    dist = {start: 0}
    preds: Dict[StoreState, List[Tuple[StoreState, str, int]]] = {start: []}
    goal_cache = {}
    winning_states: List[StoreState] = []

    reach_cache: Dict[frozenset, frozenset] = {}

    def cached_reach(source_values: frozenset):
        cached = reach_cache.get(source_values)
        if cached is None:
            cached = reach_values(source_values, comb_ops, bound)
            reach_cache[source_values] = cached
        return cached

    if _check_goal(level, start, store_ids, comb_ops, bound, goal_cache, reach_fn=cached_reach):
        winning_states.append(start)

    frontier = [start]
    depth = 0
    exhausted = False
    while frontier:
        if depth >= max_latches:
            exhausted = False
            break
        depth += 1
        next_layer: Dict[StoreState, bool] = {}
        for state in frontier:
            for si, store_id in enumerate(store_ids):
                srcs_excl = [n for n in sources_for_state(level, state, store_ids) if n.node_id != store_id]
                cand_values = cached_reach(frozenset(n.value for n in srcs_excl))
                cur_val = state.values[si]
                for v in cand_values:
                    if v == cur_val:
                        continue
                    new_vals = list(state.values)
                    new_vals[si] = v
                    new_state = StoreState(tuple(new_vals))
                    if new_state not in dist:
                        dist[new_state] = depth
                        preds[new_state] = []
                    if dist[new_state] == depth:
                        preds[new_state].append((state, store_id, v))
                        next_layer[new_state] = True
        frontier = list(next_layer.keys())
        for state in frontier:
            if state not in [w for w in winning_states]:  # cheap; state counts are small
                if _check_goal(level, state, store_ids, comb_ops, bound, goal_cache, reach_fn=cached_reach):
                    winning_states.append(state)
        if not frontier:
            exhausted = True
            break
        if winning_states and not find_all:
            break
    else:
        exhausted = True

    if not frontier and not winning_states:
        exhausted = True

    solvable = len(winning_states) > 0

    solutions: List[Solution] = []
    if solvable:
        # Solution diversity has two independent sources: different latch-event
        # sequences (the outer state-graph search) AND different combinational
        # wirings achieving the exact same goal from the exact same state (e.g.
        # a 0-latch level can still have several structurally distinct networks
        # simultaneously covering the outputs). Both must be explored for --all,
        # or genuinely distinct families get missed. Since raw candidates often
        # collapse into far fewer *families* after Sum-port/wire-order dedup, we
        # over-generate raw candidates (raw_cap) relative to max_families and let
        # the caller dedupe-then-truncate, rather than stopping the moment the
        # raw count hits max_families (which tends to yield many duplicates of
        # the same family and starve genuinely different ones).
        if find_all:
            per_phase_witness_cap = max(20, max_families * 4)
            path_cap = max(20, max_families * 4)
            raw_cap = max(60, max_families * 8)
        else:
            per_phase_witness_cap = 1
            path_cap = 1
            raw_cap = 1

        # Memoize witness searches by (source-value-set, target-value-set): many
        # different paths pass through the same state, and the final-phase
        # witness search in particular depends only on wstate, not on the path
        # taken to reach it.
        latch_witness_cache: Dict[Tuple[frozenset, int], list] = {}
        final_witness_cache: Dict[StoreState, list] = {}

        def latch_witnesses(srcs_excl, value):
            # Keyed by (node_id, value) pairs, not just values -- which node
            # holds a given value matters for step-notation provenance (e.g.
            # S1=6 and S2=6 are not interchangeable), so a value-only key would
            # let a witness computed against one node identity get reused for a
            # different one and reference a producer id that isn't live there.
            key = (frozenset((n.node_id, n.value) for n in srcs_excl), value)
            cached = latch_witness_cache.get(key)
            if cached is None:
                cached = find_covering_networks(srcs_excl, comb_ops, bound, {"_latch": value},
                                                 max_witnesses=per_phase_witness_cap)
                latch_witness_cache[key] = cached
            return cached

        def final_witnesses_for(wstate):
            cached = final_witness_cache.get(wstate)
            if cached is None:
                final_srcs = sources_for_state(level, wstate, store_ids)
                cached = find_covering_networks(final_srcs, comb_ops, bound, level.outputs,
                                                 max_witnesses=per_phase_witness_cap)
                final_witness_cache[wstate] = cached
            return cached

        for wstate in winning_states:
            if len(solutions) >= raw_cap:
                break
            paths = _reconstruct_paths(preds, start, wstate, cap=path_cap)
            for path in paths:
                if len(solutions) >= raw_cap:
                    break
                witness_lists = []
                cur = start
                ok = True
                for (store_id, value) in path:
                    srcs_excl = [n for n in sources_for_state(level, cur, store_ids) if n.node_id != store_id]
                    res = latch_witnesses(srcs_excl, value)
                    if not res:
                        ok = False
                        break
                    witness_lists.append(res)
                    si = store_ids.index(store_id)
                    new_vals = list(cur.values)
                    new_vals[si] = value
                    cur = StoreState(tuple(new_vals))
                if not ok:
                    continue

                final_witnesses = final_witnesses_for(wstate)
                if not final_witnesses:
                    continue

                for combo in itertools.product(*witness_lists, final_witnesses):
                    if len(solutions) >= raw_cap:
                        break
                    latches = []
                    for (store_id, value), (built, assignment) in zip(path, combo[:-1]):
                        built = prune_to_needed(built, assignment)
                        latches.append(LatchPhase(store_id, value, built, assignment))
                    fbuilt, fassignment = combo[-1]
                    fbuilt = prune_to_needed(fbuilt, fassignment)
                    solutions.append(Solution(latches, FinalPhase(fbuilt, fassignment), len(latches)))

    return SearchResult(
        solvable=solvable,
        bound=bound,
        max_latches=max_latches,
        exhausted=exhausted,
        solutions=solutions,
        states_explored=len(dist),
    )


def _reconstruct_paths(preds, start, target, cap=10, max_pred_branch=4):
    """Backtrack from `target` to `start` via the predecessor DAG, returning up
    to `cap` distinct paths (each a list of (store_id, value) transitions in
    forward order)."""
    if target == start:
        return [[]]
    results = []

    def bt(state, acc):
        if len(results) >= cap:
            return
        if state == start:
            results.append(list(reversed(acc)))
            return
        for (prev, store_id, value) in preds.get(state, [])[:max_pred_branch]:
            if len(results) >= cap:
                return
            acc.append((store_id, value))
            bt(prev, acc)
            acc.pop()

    bt(target, [])
    return results
