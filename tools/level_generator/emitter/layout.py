"""
CR-P8 -- node array ordering.

Implements §19.4 (the three arrays) and §19.4a (the operation grid layout).

`LevelBuilder` places operation *i* at `operation_location_groups[n-1].locations[i]`,
and those markers form columns filled top-to-bottom, left-to-right -- so an
index is a grid position, not a rank. A pair occupies a column; a triple
occupies a row. The algorithm below arranges repeated types so they read as
deliberate structure rather than scatter.

    n=1      n=2      n=3        n=4            n=5              n=6
     [0]     [0]      [0]     [0]   [2]     [0]       [3]     [0] [2] [4]
             [1]      [1]     [1]   [3]         [2]           [1] [3] [5]
                      [2]                   [1]       [4]

SEQUENCING HAZARD
-----------------
Every `slot` in the emitted solution data derives from array position. Ordering
the arrays *after* building the (type, slot) map yields a file that loads
cleanly and points every hint at the wrong node -- the worst failure mode
available, since nothing catches it short of playing the level.

This module therefore exposes exactly one entry point, `build_layout`, which
returns the ordered arrays and the map together as a single `Layout`. There is
no public way to obtain a map from an unordered array, because there is no
public way to obtain an unordered array.
"""
from __future__ import annotations

from typing import Dict, List, Optional, Sequence, Tuple

from ir import Layout, NodeEntry
from project import Project, node_type_for


class LayoutError(RuntimeError):
    """Layout could not be computed. Always fatal -- see the module docstring."""


# --------------------------------------------------------------------------
# Size groups (§19.4a)
# --------------------------------------------------------------------------
#
# ONE declaration. Adding a node type is adding a line here, nothing else.
# The unimplemented NodeTypeRegistry types (MULTIPLY, DIVIDE, INVERT, REVERSE,
# SPLIT, SUM_DIGITS, COMBINE) will need entries when they arrive.
#
# A type in neither group is an authoring error and raises -- it does not
# default to SMALL, or to ordinal-only sorting, because a silent default here
# produces a plausible-looking but wrong grid.

LARGE = "LARGE"
SMALL = "SMALL"

SIZE_GROUP: Dict[str, str] = {
    "SUM": LARGE,
    "SUBTRACT": LARGE,
    "ADD_VALUE": SMALL,
    "STORE": SMALL,
}

_SIZE_RANK = {LARGE: 0, SMALL: 1}


# --------------------------------------------------------------------------
# Shape table (§19.4a)
# --------------------------------------------------------------------------
#
# (n, count) -> shapes in priority order. Absent key == "no entry": the group
# does not claim and falls through to step 4.
#
# (4, 3) is absent deliberately: a triple can form neither a row nor a column
# in a 2x2.

SHAPE_TABLE: Dict[Tuple[int, int], Tuple[Tuple[int, ...], ...]] = {
    (3, 2): ((0, 2),),                       # top and bottom of the stack, odd node centred
    (4, 2): ((0, 1), (2, 3)),                # left column, then right column
    (5, 4): ((0, 1, 3, 4),),                 # both columns, centre left free
    (5, 3): ((0, 1, 2),),
    (5, 2): ((0, 1), (3, 4)),
    (6, 5): ((0, 1, 2, 3, 4),),
    (6, 4): ((0, 1, 2, 3),),                 # left and middle columns
    (6, 3): ((0, 2, 4), (1, 3, 5)),          # top row, then bottom row
    (6, 2): ((0, 1), (4, 5), (2, 3)),        # left, then right, then middle
}


def _size_rank(node_type: str) -> int:
    try:
        return _SIZE_RANK[SIZE_GROUP[node_type]]
    except KeyError:
        raise LayoutError(
            f"NodeType {node_type!r} is in neither the LARGE nor the SMALL size group. "
            f"Add it to SIZE_GROUP in emitter/layout.py -- a type with no size group "
            f"cannot be laid out, and defaulting it would silently produce a wrong grid."
        ) from None


def _operation_order(level, project: Project) -> List[Tuple[str, str]]:
    """Return operation (node_id, node_type) pairs in final array order.

    Steps are numbered to match §19.4a.
    """
    ops: List[Tuple[str, str]] = [
        (op_id, node_type_for(spec.type)) for op_id, spec in level.operations.items()
    ]
    n = len(ops)
    if n == 0:
        return []

    # Every type present must have a size group, whether or not it ends up in a
    # claiming group. Validating only claiming groups would let an unknown type
    # slip through on any level that happens to use exactly one of it.
    for _, node_type in ops:
        _size_rank(node_type)

    # Stable, id-sorted within a type so two nodes of the same type always land
    # in the same relative order. Nothing downstream distinguishes them, but
    # byte-identical output across runs is an acceptance criterion.
    by_type: Dict[str, List[str]] = {}
    for op_id, node_type in sorted(ops, key=lambda p: p[0]):
        by_type.setdefault(node_type, []).append(op_id)

    slots: List[Optional[str]] = [None] * n
    claimed: set = set()

    def claim(shape: Sequence[int], ids: Sequence[str]) -> None:
        for slot_index, op_id in zip(shape, ids):
            slots[slot_index] = op_id
            claimed.add(slot_index)

    # Step 1 -- form groups. Stores are excluded from grouping entirely; every
    # rule below concerns non-store types only.
    claiming = [
        (node_type, ids) for node_type, ids in by_type.items()
        if node_type != "STORE" and len(ids) >= 2
    ]

    # Step 2 -- sort claiming groups: count descending, LARGE before SMALL,
    # then NodeType ordinal ascending.
    claiming.sort(
        key=lambda pair: (-len(pair[1]), _size_rank(pair[0]), project.ordinal(pair[0]))
    )

    # Step 3 -- each group claims slots, in that order.
    unclaimed_after_step3 = set(by_type)  # type names still needing step 4
    for node_type, ids in claiming:
        shapes = SHAPE_TABLE.get((n, len(ids)))
        if shapes is None:
            continue  # no entry: falls through to step 4
        chosen = next((s for s in shapes if all(i not in claimed for i in s)), None)
        if chosen is None:
            # Every listed shape blocked -> claim the lowest-indexed unclaimed
            # slots instead. (n=6 with 3+2 reaches this: the triple takes
            # {0,2,4}, all three of the pair's shapes are blocked, and the pair
            # lands on {1,3}.)
            free = [i for i in range(n) if i not in claimed]
            if len(free) < len(ids):
                raise LayoutError(
                    f"Layout ran out of slots placing {len(ids)} {node_type} nodes "
                    f"in a grid of {n}. This should be unreachable; the shape table "
                    f"or the group sort is wrong."
                )
            chosen = tuple(free[: len(ids)])
        claim(chosen, ids)
        unclaimed_after_step3.discard(node_type)

    # Step 4 -- everything unclaimed (singles, groups with no shape entry, and
    # all stores) fills the remaining slots in ascending index: non-stores
    # first by NodeType ordinal, then stores. Stores landing last is a
    # consequence of this ordering, not a separate rule that could conflict
    # with one.
    leftovers: List[str] = []
    remaining_types = [t for t in by_type if t in unclaimed_after_step3]
    non_stores = sorted(
        (t for t in remaining_types if t != "STORE"), key=project.ordinal
    )
    for node_type in non_stores:
        leftovers.extend(by_type[node_type])
    if "STORE" in remaining_types:
        leftovers.extend(by_type["STORE"])

    free_slots = [i for i in range(n) if i not in claimed]
    if len(free_slots) != len(leftovers):
        raise LayoutError(
            f"Layout accounting error: {len(free_slots)} free slots for "
            f"{len(leftovers)} unplaced nodes in a grid of {n}."
        )
    for slot_index, op_id in zip(free_slots, leftovers):
        slots[slot_index] = op_id

    if any(s is None for s in slots):
        raise LayoutError(f"Layout left a hole in a grid of {n}: {slots!r}")

    type_of = {op_id: node_type for op_id, node_type in ops}
    return [(op_id, type_of[op_id]) for op_id in slots]  # type: ignore[arg-type]


def build_layout(level, project: Project) -> Layout:
    """The three ordered arrays and the (type, slot) map, as one object.

    §19.4:
      - inputs  : one entry per `inputs` entry, ascending by value
      - operations: ordered per §19.4a
      - outputs : one entry per `outputs` entry, ascending by value

    Input values and output targets are guaranteed distinct by §3, so ascending
    value is a total order on each and no tiebreak is needed. We assert that
    rather than assume it -- if the guarantee ever fails, a stable sort would
    quietly produce a key-order-dependent layout.
    """
    for label, mapping in (("input", level.inputs), ("output", level.outputs)):
        values = list(mapping.values())
        if len(set(values)) != len(values):
            raise LayoutError(
                f"{level.name}: {label} values are not distinct ({values}). "
                f"§3 guarantees they are, and ascending-value ordering is only a "
                f"total order if they are."
            )

    inputs = tuple(
        NodeEntry(node_id=node_id, node_type="INPUT", slot=i, value=value)
        for i, (node_id, value) in enumerate(
            sorted(level.inputs.items(), key=lambda kv: kv[1])
        )
    )
    outputs = tuple(
        NodeEntry(node_id=node_id, node_type="OUTPUT", slot=i, value=value)
        for i, (node_id, value) in enumerate(
            sorted(level.outputs.items(), key=lambda kv: kv[1])
        )
    )

    # Operations: slot is the 0-based index among nodes of the SAME NodeType,
    # in the final array order (§19.5) -- not the array index.
    per_type_counter: Dict[str, int] = {}
    operations: List[NodeEntry] = []
    for op_id, node_type in _operation_order(level, project):
        slot = per_type_counter.get(node_type, 0)
        per_type_counter[node_type] = slot + 1
        spec = level.operations[op_id]
        operations.append(
            NodeEntry(
                node_id=op_id,
                node_type=node_type,
                slot=slot,
                # §19.7: ADD_VALUE carries its *offset*. SUM/SUBTRACT/STORE
                # carry nothing -- Store's value in particular is the captured
                # runtime value and must never be seeded from level data.
                value=spec.value if node_type == "ADD_VALUE" else None,
            )
        )

    by_id: Dict[str, NodeEntry] = {}
    for entry in list(inputs) + operations + list(outputs):
        if entry.node_id in by_id:
            raise LayoutError(f"Duplicate node id {entry.node_id!r} in {level.name}.")
        by_id[entry.node_id] = entry

    return Layout(
        inputs=inputs,
        operations=tuple(operations),
        outputs=outputs,
        by_id=by_id,
    )
