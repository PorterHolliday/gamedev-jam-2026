"""
Combinational reachability within a single "phase" (the memoryless network live
between store-latch events).

Two flavors are provided:

- reach_values(): fast value-only closure. Used for pruning and for enumerating
  candidate values a store latch could take on.
- find_covering_networks(): full network construction with node provenance, used
  to actually witness a solution (needed for step notation). Each operation node
  may appear in a constructed network at most once (it is a single physical node
  with one output), but its output may fan out to unlimited consumers, and source
  values (inputs / already-latched stores) may likewise be reused without limit.
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Dict, FrozenSet, List, Tuple


def in_bound(v: int, bound: Tuple[int, int]) -> bool:
    return bound[0] <= v <= bound[1]


def reach_values(source_values: FrozenSet[int], ops: dict, bound: Tuple[int, int]) -> FrozenSet[int]:
    """All values obtainable at ANY node (source or op output) in some legal
    acyclic network built from `sources` using `ops`, each op used at most once.
    Pure value-level closure (no provenance) -- used for pruning / candidate
    enumeration, not for emitting solutions."""
    ops_items = list(ops.items())
    all_vals = set(source_values)
    seen = set()

    def dfs(used: frozenset, pool: frozenset):
        key = (used, pool)
        if key in seen:
            return
        seen.add(key)
        for op_id, spec in ops_items:
            if op_id in used:
                continue
            new_used = used | frozenset((op_id,))
            if spec.type == "add":
                for v in pool:
                    nv = v + spec.value
                    if not in_bound(nv, bound):
                        continue
                    all_vals.add(nv)
                    dfs(new_used, pool | frozenset((nv,)))
            else:  # sum / subtract
                for v1 in pool:
                    for v2 in pool:
                        nv = v1 + v2 if spec.type == "sum" else v1 - v2
                        if not in_bound(nv, bound):
                            continue
                        all_vals.add(nv)
                        dfs(new_used, pool | frozenset((nv,)))

    dfs(frozenset(), frozenset(source_values))
    return frozenset(all_vals)


@dataclass(frozen=True)
class PlacedNode:
    node_id: str
    value: int
    kind: str              # 'source' | 'add' | 'sum' | 'subtract'
    inputs: tuple = ()      # producer node ids: (in,) for add; (top, bottom) for sum/subtract


def find_covering_networks(
    source_nodes: List[PlacedNode],
    ops: dict,
    bound: Tuple[int, int],
    targets: Dict[str, int],
    max_witnesses: int = 6,
    node_budget: int = 300000,
) -> List[Tuple[List[PlacedNode], Dict[str, str]]]:
    """Search for networks whose live node outputs simultaneously cover every
    value in `targets` (a dict of label -> required value; labels are typically
    output ids, or a single synthetic label for a store-latch target).

    Returns a list of (built_op_nodes, assignment) pairs:
      - built_op_nodes: the op nodes placed, in build order (may include nodes
        not on the critical path -- callers should prune via backward walk from
        the assignment before rendering).
      - assignment: label -> node_id of the node whose current value equals the
        target for that label.

    Multiple witnesses may be returned when different underlying wiring achieves
    the same coverage; this is a source of solution-family diversity in addition
    to the outer store-state search.
    """
    target_values = set(targets.values())
    if not target_values:
        return [([], {})]

    ops_items = list(ops.items())
    results: List[Tuple[List[PlacedNode], Dict[str, str]]] = []
    visited = set()
    budget = [node_budget]

    producer_of: Dict[int, str] = {}
    for sn in source_nodes:
        producer_of.setdefault(sn.value, sn.node_id)

    def record_if_covering(pool_map: Dict[int, str], built: List[PlacedNode]):
        if target_values.issubset(pool_map.keys()):
            assignment = {label: pool_map[tv] for label, tv in targets.items()}
            results.append((list(built), assignment))

    def dfs(used: frozenset, pool_map: Dict[int, str], built: List[PlacedNode]):
        if len(results) >= max_witnesses or budget[0] <= 0:
            return
        budget[0] -= 1

        record_if_covering(pool_map, built)
        if len(results) >= max_witnesses:
            return

        key = (used, frozenset(pool_map.keys()))
        if key in visited:
            return
        visited.add(key)

        for op_id, spec in ops_items:
            if op_id in used:
                continue
            new_used = used | frozenset((op_id,))
            if spec.type == "add":
                for v, pid in list(pool_map.items()):
                    nv = v + spec.value
                    if not in_bound(nv, bound):
                        continue
                    node = PlacedNode(op_id, nv, "add", (pid,))
                    new_pool = dict(pool_map)
                    new_pool.setdefault(nv, op_id)
                    dfs(new_used, new_pool, built + [node])
                    if len(results) >= max_witnesses or budget[0] <= 0:
                        return
            else:
                for v1, p1 in list(pool_map.items()):
                    for v2, p2 in list(pool_map.items()):
                        nv = v1 + v2 if spec.type == "sum" else v1 - v2
                        if not in_bound(nv, bound):
                            continue
                        node = PlacedNode(op_id, nv, spec.type, (p1, p2))
                        new_pool = dict(pool_map)
                        new_pool.setdefault(nv, op_id)
                        dfs(new_used, new_pool, built + [node])
                        if len(results) >= max_witnesses or budget[0] <= 0:
                            return

    dfs(frozenset(), dict(producer_of), [])
    return results


def prune_to_needed(built: List[PlacedNode], assignment: Dict[str, str]) -> List[PlacedNode]:
    """Keep only the op nodes that are transitively required to produce the
    values in `assignment`, discarding dead-end branches the search explored
    but didn't end up needing."""
    by_id = {n.node_id: n for n in built}
    needed = set(assignment.values())
    worklist = list(needed)
    while worklist:
        nid = worklist.pop()
        node = by_id.get(nid)
        if node is None:
            continue  # it's a source node, terminal
        for pid in node.inputs:
            if pid not in needed:
                needed.add(pid)
                worklist.append(pid)
    return [n for n in built if n.node_id in needed]
