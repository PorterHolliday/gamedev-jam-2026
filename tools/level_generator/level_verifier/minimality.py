"""
Leave-one-out minimality analysis (spec section 3, point 3).
"""
from __future__ import annotations
from typing import List, Tuple

from model import Level
from solver import solve


def minimality_report(level: Level, bound, max_latches) -> Tuple[bool, List[Tuple[str, bool]]]:
    """Returns (is_minimal, [(node_id, required)]).
    required=True means deleting that node makes the level unsolvable (good).
    required=False means the level is still solvable without it (level is NOT minimal)."""
    rows = []
    for node_id in level.all_deletable_nodes():
        sub_level = level.without_node(node_id)
        result = solve(sub_level, bound=bound, max_latches=max_latches, find_all=False)
        required = not result.solvable
        rows.append((node_id, required, result.exhausted))
    is_minimal = all(r[1] for r in rows)
    return is_minimal, rows
