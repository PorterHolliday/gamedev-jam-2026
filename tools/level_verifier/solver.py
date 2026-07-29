"""
Outer search over store contents (the only durable state between phases).
"""
from __future__ import annotations
import itertools
from dataclasses import dataclass, field
from typing import Dict, List, Tuple

from reach import PlacedNode, reach_values, find_covering_networks, prune_to_needed
from model import Level
from signature import literal_signature


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
                # Sorted rather than iterated in raw (hash-seed-dependent)
                # frozenset order: exploration order feeds directly into which
                # states get discovered first, which matters once raw_cap /
                # examine_budget kick in -- without a fixed order, re-running
                # the exact same level could report a different family count
                # from run to run purely because of PYTHONHASHSEED.
                for v in sorted(cand_values):
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
        # Family identity (see notation.py) depends only on a solution's FINAL
        # store contents and final wiring -- never on how the stores got there.
        # final_witnesses_for(wstate) depends only on wstate's contents, not on
        # the path used to reach it, so that's the one place genuine family
        # diversity comes from and the one search worth widening. By contrast:
        #   - latch-transition witnesses only affect the *route* to a state,
        #     which is invisible to family identity, so any single valid one
        #     will do (latch_witness_cap = 1).
        #   - multiple paths to the same state are similarly irrelevant to
        #     family identity, and the BFS already records only shortest-depth
        #     predecessor edges, so a single reconstructed path is always
        #     minimal-latch-count already (path_cap = 1).
        # This both matches the new family definition and is a large speedup:
        # the search no longer explores the combinatorial product of path and
        # latch-witness choices that used to just produce different routes to
        # identical destinations.
        if find_all:
            latch_witness_cap = 1
            final_witness_cap = max(20, max_families * 4)
            path_cap = 1
            raw_cap = max(30, max_families * 4)
            examine_budget = max(4000, max_families * 400)
        else:
            latch_witness_cap = 1
            final_witness_cap = 1
            path_cap = 1
            raw_cap = 1
            examine_budget = 10

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
                                                 max_witnesses=latch_witness_cap)
                latch_witness_cache[key] = cached
            return cached

        def final_witnesses_for(wstate):
            cached = final_witness_cache.get(wstate)
            if cached is None:
                final_srcs = sources_for_state(level, wstate, store_ids)
                cached = find_covering_networks(final_srcs, comb_ops, bound, level.outputs,
                                                 max_witnesses=final_witness_cap)
                final_witness_cache[wstate] = cached
            return cached

        seen_signatures = set()
        examined = 0
        done = False

        for wstate in winning_states:
            if done:
                break
            paths = _reconstruct_paths(preds, start, wstate, cap=path_cap)
            for path in paths:
                if done:
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
                    examined += 1
                    if examined > examine_budget:
                        done = True
                        break
                    latches = []
                    for (store_id, value), (built, assignment) in zip(path, combo[:-1]):
                        built = prune_to_needed(built, assignment)
                        latches.append(LatchPhase(store_id, value, built, assignment))
                    fbuilt, fassignment = combo[-1]
                    fbuilt = prune_to_needed(fbuilt, fassignment)
                    latches, fbuilt, fassignment = _prefer_cheaper_producers(level, latches, fbuilt, fassignment)
                    pruned_latches = _prune_dead_latches(latches, fbuilt, fassignment, store_ids)
                    candidate = Solution(pruned_latches, FinalPhase(fbuilt, fassignment), len(pruned_latches))

                    sig = literal_signature(candidate)
                    if sig in seen_signatures:
                        continue  # padding duplicate after pruning -- don't count it, keep looking
                    seen_signatures.add(sig)
                    solutions.append(candidate)
                    if len(solutions) >= raw_cap:
                        done = True
                        break

    return SearchResult(
        solvable=solvable,
        bound=bound,
        max_latches=max_latches,
        exhausted=exhausted,
        solutions=solutions,
        states_explored=len(dist),
    )


def _prefer_cheaper_producers(level: Level, latches: List[LatchPhase],
                               final_built: List[PlacedNode], final_assignment: Dict[str, str]):
    """Whenever a producer reference points at a store, but some other source
    (an input, or a store that was latched earlier) already holds the exact
    same value at that point, rewrite the reference to the cheaper one.

    This matters because the search finds witnesses state-by-state: if two
    stores end up holding the same value (one because it was latched earlier
    for its own reasons, the other because the search happened to copy that
    same value into it later), a witness built against that later state may
    reference the *newer* copy purely because that's what the search saw,
    even though the older, already-available one would have worked identically
    and made the newer latch unnecessary. Without this rewrite, that redundant
    copy survives dead-latch pruning (it looks "used") and produces a
    needlessly-padded "different" family. This only ever substitutes a
    same-valued producer, so it never changes what the network computes --
    it just prefers not to require the extra latch event when something
    already on hand would do."""
    value_of: Dict[str, int] = dict(level.inputs)
    available_since: Dict[str, int] = {iid: -1 for iid in level.inputs}

    def cheapest_for(value, exclude=None):
        candidates = [pid for pid, v in value_of.items() if v == value and pid != exclude]
        if not candidates:
            return None
        return min(candidates, key=lambda pid: (available_since[pid], pid))

    def remap(pid, exclude=None):
        v = value_of.get(pid)
        if v is None:
            return pid  # not a tracked source (e.g. an op-node id) -- leave alone
        best = cheapest_for(v, exclude=exclude)
        return best if best is not None else pid

    def remap_node(node: PlacedNode, exclude=None) -> PlacedNode:
        return PlacedNode(node.node_id, node.value, node.kind,
                           tuple(remap(p, exclude=exclude) for p in node.inputs))

    new_latches = []
    for idx, latch in enumerate(latches):
        # Exclude the store being written from its own candidate producers --
        # it can't be a source for its own new value (that's the cycle rule),
        # and at this point in the walk value_of[latch.store_id] is still its
        # *old* (about to be overwritten) value, so it would otherwise look
        # like a spuriously eligible candidate.
        new_built = [remap_node(n, exclude=latch.store_id) for n in latch.built]
        new_producer = remap(latch.assignment["_latch"], exclude=latch.store_id)
        new_latches.append(LatchPhase(latch.store_id, latch.value, new_built, {"_latch": new_producer}))
        value_of[latch.store_id] = latch.value
        available_since[latch.store_id] = idx

    new_final_built = [remap_node(n) for n in final_built]
    new_final_assignment = {k: remap(v) for k, v in final_assignment.items()}
    return new_latches, new_final_built, new_final_assignment


def _prune_dead_latches(latches: List[LatchPhase], final_built: List[PlacedNode],
                         final_assignment: Dict[str, str], store_ids: List[str]) -> List[LatchPhase]:
    """Drop latch events that never causally contribute to the final network --
    e.g. a trailing latch into a store nobody reads from again, or a store that
    briefly holds an intermediate value on the way to being overwritten by a
    later latch that's the one actually used. Without this, the outer search
    treats every reachable store-content state as its own distinct "winning
    state" even when the only difference from another one is an unused store
    value, which blows up the reported family count with meaningless padding
    (see: ratcheting past a target and back, or leaving a second store on some
    arbitrary leftover value after the real solution is already complete).

    This is a backward liveness sweep: start from the store ids the final
    network actually reads from, walk the latch sequence in reverse, and keep
    only latches whose store id is currently "needed." Keeping a latch adds
    whatever store ids *it* reads from to the needed set (since that's how its
    own value got built), and removes its own store id (whatever that store
    held before this latch is now irrelevant -- this event fully determines
    what matters going forward from here)."""
    store_id_set = set(store_ids)
    needed = set()
    for node in final_built:
        for pid in node.inputs:
            if pid in store_id_set:
                needed.add(pid)
    for v in final_assignment.values():
        if v in store_id_set:
            needed.add(v)

    kept_reversed = []
    for latch in reversed(latches):
        if latch.store_id not in needed:
            continue  # dead: nothing downstream ever reads this value
        kept_reversed.append(latch)
        needed.discard(latch.store_id)
        for node in latch.built:
            for pid in node.inputs:
                if pid in store_id_set:
                    needed.add(pid)
        producer = latch.assignment.get("_latch")
        if producer in store_id_set:
            needed.add(producer)
    return list(reversed(kept_reversed))


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
