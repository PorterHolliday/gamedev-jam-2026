"""
§19.10 -- reducing solution families to distinct paths.

`verify.py --all` reports families that differ in build order. Families sharing
one *final configuration* remain the same path in game and must not be
duplicated: a duplicate makes path scoring ambiguous for no benefit.

Keying is on the final configuration only:

  - store_values: sorted (slot, value) over stores read in the final phase
  - wires: the final phase's set of (from_type, from_slot, from_port, to_type,
    to_slot, to_port), with to_port dropped when to_type is a commutative type

then quotiented by permutations of interchangeable same-type slots.

WHICH SLOTS ARE ACTUALLY INTERCHANGEABLE
----------------------------------------
§19.10 says "permutations of same-type slots", justified by "the hint system
performs exactly that permutation search at runtime". It does -- but
`SolutionPath._candidates_for_type` additionally prunes those permutations by
`_slot_value_requirements` for types where `NodeTypeRegistry.has_fixed_value`
is true. So the runtime's effective symmetry is:

  - SUM, SUBTRACT, STORE      -- freely permutable (no value to prune on)
  - INPUT, OUTPUT             -- not permutable; values are distinct by §3, so
                                 pruning pins each slot to one node
  - ADD_VALUE                 -- permutable only among nodes with the SAME
                                 offset; two Add nodes with different offsets
                                 compute different things

Quotienting by the unrestricted reading would collapse genuinely distinct
paths, and a missing path is the more expensive error: for hints it degrades
guidance, but for challenge mode it means a player can find a legitimate
solution the game cannot credit. This matches `notation._symmetry_classes`
exactly, which is the third independent statement of the same rule.
"""
from __future__ import annotations

import itertools
from typing import Dict, List, Sequence, Tuple

from ir import Layout, Path
from project import Project


def _symmetry_classes(layout: Layout, project: Project) -> List[Tuple[str, Tuple[int, ...]]]:
    """Slot groups that are interchangeable, as (NodeType, slots).

    Only groups of 2+ are returned -- a group of one has nothing to swap with.
    """
    groups: Dict[Tuple[str, object], List[int]] = {}
    for entry in layout.operations:
        if entry.node_type in project.fixed_value:
            # ADD_VALUE and friends: interchangeable only at equal value.
            key = (entry.node_type, entry.value)
        else:
            key = (entry.node_type, None)
        groups.setdefault(key, []).append(entry.slot)
    return [
        (node_type, tuple(sorted(slots)))
        for (node_type, _), slots in sorted(groups.items(), key=lambda kv: str(kv[0]))
        if len(slots) >= 2
    ]


def _final_key(path: Path, layout: Layout, project: Project,
               remap: Dict[Tuple[str, int], int]) -> tuple:
    final = path.phases[-1]

    def ref(node_id: str) -> Tuple[str, int]:
        node_type, slot = layout.ref(node_id)
        return (node_type, remap.get((node_type, slot), slot))

    wires = []
    for w in final.wires:
        from_type, from_slot = ref(w.from_id)
        to_type, to_slot = ref(w.to_id)
        # Sum is commutative and NodeTypeRegistry says so, so the hint system
        # relaxes port matching for it -- two families differing only in which
        # Sum port a wire lands on are the same configuration in game.
        to_port = None if to_type in project.commutative else w.to_port
        wires.append((from_type, from_slot, w.from_port, to_type, to_slot, to_port))

    store_values = []
    read_in_final = {w.from_id for w in final.wires}
    for phase in path.phases:
        if phase.terminator is None:
            continue
        if phase.terminator.store_id in read_in_final:
            _, slot = ref(phase.terminator.store_id)
            store_values.append((slot, phase.terminator.value))

    return (tuple(sorted(set(store_values))), tuple(sorted(set(wires), key=repr)))


def _canonical_key(path: Path, layout: Layout, project: Project) -> tuple:
    """Lexicographically smallest final-configuration key over every
    permutation of interchangeable slots."""
    classes = _symmetry_classes(layout, project)
    if not classes:
        return _final_key(path, layout, project, {})

    best = None
    per_class = [itertools.permutations(slots) for _, slots in classes]
    for choice in itertools.product(*per_class):
        remap: Dict[Tuple[str, int], int] = {}
        for (node_type, slots), perm in zip(classes, choice):
            for original, replacement in zip(slots, perm):
                remap[(node_type, original)] = replacement
        key = repr(_final_key(path, layout, project, remap))
        if best is None or key < best:
            best = key
    return best


def _journey_cost(path: Path) -> Tuple[int, int]:
    """Sort key for "shortest journey": fewest latch events, then fewest
    connections.

    §19.10 says "fewest transcript steps" as the tiebreak. Under phased
    authoring the transcript is no longer what the player works through -- the
    emitted phases are -- so total connection count across phases is the
    measure that corresponds to what §19.10 was reaching for. The two agree on
    ordering in every corpus level; where they could differ, this one is the
    one the player actually experiences.
    """
    latches = sum(1 for p in path.phases if p.terminator is not None)
    return (latches, sum(len(p.wires) for p in path.phases))


def collapse_paths(paths: Sequence[Path], layout: Layout, project: Project) -> List[Path]:
    """Collapse to one path per distinct final configuration, keeping the
    shortest journey in each class, ordered shortest-first."""
    groups: Dict[str, List[Path]] = {}
    order: List[str] = []
    for path in paths:
        key = repr(_canonical_key(path, layout, project))
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(path)

    representatives = [min(groups[k], key=_journey_cost) for k in order]
    representatives.sort(key=_journey_cost)
    return representatives
