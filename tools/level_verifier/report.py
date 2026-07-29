"""
Human-readable report generation for the CLI.
"""
from __future__ import annotations
from math import gcd
from typing import Tuple

from model import Level
from solver import solve, SearchResult
from notation import render_solution, dedupe_families
from minimality import minimality_report


def bound_str(bound: Tuple[int, int], max_latches: int) -> str:
    return f"[{bound[0]}, {bound[1]}], <= {max_latches} latch events"


def header_lines(level: Level) -> list:
    lines = [f"Level: {level.name}"]
    for w in level.warnings:
        lines.append(f"Warning: {w}")
    return lines


def solvability_line(level: Level, result: SearchResult, bound, max_latches) -> str:
    if result.solvable:
        return f"Solvable: YES (within bound {bound_str(bound, max_latches)})"
    if result.exhausted:
        return (f"Solvable: NO -- proven unsolvable within bound {bound_str(bound, max_latches)} "
                f"(full state space explored)")
    else:
        return (f"Solvable: NO -- no solution found within bound {bound_str(bound, max_latches)} "
                f"(search truncated by the latch cap; a solution using more latches cannot be ruled out)")


def ratchet_note(level: Level) -> str:
    stores = level.store_ops()
    if len(stores) < 2:
        return ""
    adds = [abs(spec.value) for spec in level.combinational_ops().values() if spec.type == "add" and spec.value]
    if not adds:
        return ("Note: 2+ stores present but no Add nodes to derive a step size from; ratcheting behavior "
                "depends on Sum/Subtract combinations and must be read from the search, not a simple lattice.")
    g = adds[0]
    for a in adds[1:]:
        g = gcd(g, a)
    return (f"Ratcheting sanity check: with the declared Add step sizes, a naive gcd-lattice would reach "
            f"seed + k*{g} for integer k. This is a heuristic only -- Sum/Subtract nodes can derive additional "
            f"step sizes (e.g. by doubling), so treat this as a sanity check, not a substitute for the search.")


def full_report(level: Level, bound, max_latches, find_all=False, max_families=10) -> Tuple[str, int]:
    lines = []
    lines.append(f"Level: {level.name}")
    for w in level.warnings:
        lines.append(f"Warning: {w}")
    lines.append("")

    result = solve(level, bound=bound, max_latches=max_latches, find_all=find_all, max_families=max_families)
    lines.append(solvability_line(level, result, bound, max_latches))

    exit_code = 0
    if result.solvable:
        families = dedupe_families(result.solutions)
        if find_all:
            families = families[:max_families]
        lines.append("")
        if find_all:
            lines.append(f"Found {len(families)} distinct solution family/families:")
            for i, sol in enumerate(families, 1):
                lines.append("")
                lines.append(f"--- Family {i} ({sol.latch_count} latch event(s)) ---")
                lines.extend(render_solution(level, sol))
        else:
            sol = families[0]
            lines.append(f"Solution ({sol.latch_count} latch event(s)):")
            lines.extend(render_solution(level, sol))
    else:
        exit_code = 1

    note = ratchet_note(level)
    if note:
        lines.append("")
        lines.append(note)

    lines.append("")
    is_minimal, rows = minimality_report(level, bound, max_latches)
    if result.solvable:
        lines.append(f"Minimality: {'MINIMAL' if is_minimal else 'NOT MINIMAL'} "
                      f"(within bound {bound_str(bound, max_latches)})")
        for node_id, required, exhausted in rows:
            status = "required (unsolvable without it)" if required else "NOT required (still solvable without it)"
            caveat = "" if exhausted else "  [leave-one-out check truncated by latch cap]"
            lines.append(f"  - {node_id}: {status}{caveat}")
        if not is_minimal and exit_code == 0:
            exit_code = 2
    else:
        lines.append("Minimality: not evaluated (level is unsolvable)")

    return "\n".join(lines), exit_code


def solve_only_report(level: Level, bound, max_latches) -> Tuple[str, int]:
    result = solve(level, bound=bound, max_latches=max_latches, find_all=False, max_families=1)
    lines = header_lines(level) + [solvability_line(level, result, bound, max_latches)]
    if result.solvable:
        sol = dedupe_families(result.solutions)[0]
        lines.append("")
        lines.append(f"Solution ({sol.latch_count} latch event(s)):")
        lines.extend(render_solution(level, sol))
        return "\n".join(lines), 0
    return "\n".join(lines), 1


def all_report(level: Level, bound, max_latches, max_families=10) -> Tuple[str, int]:
    result = solve(level, bound=bound, max_latches=max_latches, find_all=True, max_families=max_families)
    lines = header_lines(level) + [solvability_line(level, result, bound, max_latches)]
    if result.solvable:
        families = dedupe_families(result.solutions)[:max_families]
        lines.append("")
        lines.append(f"Found {len(families)} distinct solution family/families:")
        for i, sol in enumerate(families, 1):
            lines.append("")
            lines.append(f"--- Family {i} ({sol.latch_count} latch event(s)) ---")
            lines.extend(render_solution(level, sol))
        return "\n".join(lines), 0
    return "\n".join(lines), 1


def minimality_only_report(level: Level, bound, max_latches) -> Tuple[str, int]:
    result = solve(level, bound=bound, max_latches=max_latches, find_all=False, max_families=1)
    lines = header_lines(level) + [solvability_line(level, result, bound, max_latches)]
    if not result.solvable:
        lines.append("Minimality: not evaluated (level is unsolvable)")
        return "\n".join(lines), 1
    is_minimal, rows = minimality_report(level, bound, max_latches)
    lines.append("")
    lines.append(f"Minimality: {'MINIMAL' if is_minimal else 'NOT MINIMAL'} "
                  f"(within bound {bound_str(bound, max_latches)})")
    for node_id, required, exhausted in rows:
        status = "required (unsolvable without it)" if required else "NOT required (still solvable without it)"
        caveat = "" if exhausted else "  [leave-one-out check truncated by latch cap]"
        lines.append(f"  - {node_id}: {status}{caveat}")
    return "\n".join(lines), (0 if is_minimal else 2)
