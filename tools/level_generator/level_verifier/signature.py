"""
Literal (non-symmetry) canonical signature for a Solution. Two solutions with
the same signature are identical up to Sum port order (commutative) and the
order independent wires are placed within a phase -- both already erased by
using a frozenset of node descriptions rather than the build-order list.

This lives in its own module (rather than solver.py or notation.py) because
both need it: solver.py uses it for cheap incremental dedup while generating
candidates (so search effort isn't wasted piling up exact duplicates), and
notation.py builds its symmetry-aware family dedup on top of it. Neither
solver.py nor notation.py may import the other (notation.py already imports
Solution/LatchPhase/FinalPhase from solver.py), so this shared piece is
factored out to avoid a circular import.
"""
from __future__ import annotations
from typing import List

from reach import PlacedNode


def edge_set(built: List[PlacedNode]):
    sig = []
    for n in built:
        if n.kind == "sum":
            # commutative: normalize the pair of producers as unordered
            sig.append((n.node_id, "sum", frozenset(n.inputs)))
        elif n.kind == "add":
            sig.append((n.node_id, "add", n.inputs))
        elif n.kind == "subtract":
            sig.append((n.node_id, "subtract", n.inputs))
    return frozenset(sig)


def literal_signature(solution):
    parts = []
    for latch in solution.latches:
        parts.append(("latch", latch.store_id, latch.value, edge_set(latch.built), latch.assignment["_latch"]))
    parts.append(("final", edge_set(solution.final.built), frozenset(solution.final.assignment.items())))
    return tuple(parts)
