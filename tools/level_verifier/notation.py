"""
Renders a Solution into the game's step notation (see spec section 6), and
provides a canonical signature used to collapse equivalent solutions into
"families" (Sum port order and independent-wire reordering don't count as a
different family; Subtract port order does).
"""
from __future__ import annotations
from typing import List, Dict, Tuple

from solver import Solution
from model import Level
from reach import PlacedNode


def _port_of(kind: str, idx: int):
    if kind in ("sum", "subtract"):
        return "top" if idx == 0 else "bottom"
    return None


def render_solution(level: Level, solution: Solution) -> List[str]:
    lines: List[str] = []
    step_no = [0]
    port_state: Dict[Tuple[str, object], str] = {}
    value_of: Dict[str, int] = dict(level.inputs)

    def connect(producer_id: str, target_id: str, port):
        key = (target_id, port)
        cur = port_state.get(key)
        if cur == producer_id:
            return
        step_no[0] += 1
        pv = value_of[producer_id]
        suffix = f" {port}" if port else ""
        lines.append(f"{step_no[0]}. Connect {producer_id} ({pv}) → {target_id}{suffix}")
        if cur is not None:
            lines.append(f"   [auto-severs {cur} → {target_id}{suffix}]")
        port_state[key] = producer_id

    def place_node(node: PlacedNode):
        for idx, pid in enumerate(node.inputs):
            connect(pid, node.node_id, _port_of(node.kind, idx))
        value_of[node.node_id] = node.value

    for latch in solution.latches:
        for node in latch.built:
            place_node(node)
        producer_id = latch.assignment["_latch"]
        connect(producer_id, latch.store_id, None)
        lines.append(f"   [{latch.store_id} latches {latch.value}; its input auto-disconnects]")
        port_state[(latch.store_id, None)] = None
        value_of[latch.store_id] = latch.value

    for node in solution.final.built:
        place_node(node)
    for output_id, producer_id in sorted(solution.final.assignment.items()):
        connect(producer_id, output_id, None)

    return lines


def canonical_signature(solution: Solution):
    """A hashable signature that's equal for two solutions iff they differ only
    by Sum port order or by the order independent wires are placed within a
    phase. Subtract port order and the sequence of latch events both matter."""

    def edge_set(built: List[PlacedNode]):
        # Sum ports are commutative (normalize as an unordered pair); subtract
        # and add ports are order-sensitive (kept as an ordered tuple).
        sig = []
        for n in built:
            if n.kind == "sum":
                sig.append((n.node_id, "sum", frozenset(n.inputs)))
            elif n.kind == "add":
                sig.append((n.node_id, "add", n.inputs))
            elif n.kind == "subtract":
                sig.append((n.node_id, "subtract", n.inputs))
        return frozenset(sig)

    parts = []
    for latch in solution.latches:
        parts.append(("latch", latch.store_id, latch.value, edge_set(latch.built), latch.assignment["_latch"]))
    final_sig = edge_set(solution.final.built)
    parts.append(("final", final_sig, frozenset(solution.final.assignment.items())))
    return tuple(parts)


def dedupe_families(solutions: List[Solution]) -> List[Solution]:
    seen = set()
    out = []
    for s in solutions:
        sig = canonical_signature(s)
        if sig in seen:
            continue
        seen.add(sig)
        out.append(s)
    return out
