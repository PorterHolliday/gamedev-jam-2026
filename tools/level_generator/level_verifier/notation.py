"""
Renders a Solution into the game's step notation (see spec section 6), and
provides a canonical signature used to collapse equivalent solutions into
"families".

Family identity is defined by *destination*, not *journey*: two solutions are
the same family iff they end up with the same values latched in the same
(functionally-interchangeable) stores, wired to the outputs the same way. How
the stores got to hold those values -- which route was used, how many latches
it took, what intermediate scratch values passed through along the way -- is
part of "how you play it," not part of what makes one solution meaningfully
different from another to a player looking at the finished board. This
matches the game's own memoryless-between-latches semantics: the live network
only ever depends on current store contents, never on how they got there.

Within that end-state comparison, "the same" additionally accounts for:

  - Sum port order (Sum is commutative), or the order independent wires are
    placed within the final phase -- Subtract port order still matters.
  - *which* physical node plays a role, among nodes that are functionally
    interchangeable: any two Sum nodes, any two Subtract nodes, any two Store
    nodes, or two Add nodes with the *same* value (two Add nodes with
    different values are NOT interchangeable -- swapping them would change
    what the network computes). Input and Output nodes are never
    interchangeable, since the level design guarantees their values/targets
    are distinct.

When several raw solutions collapse into one family, the shortest one is kept
as the worked example (fewest latch events, then fewest rendered connect
steps) -- that's the version a player is most likely to actually find.
"""
from __future__ import annotations
import itertools
from typing import Dict, List, Tuple

from solver import Solution, LatchPhase, FinalPhase
from model import Level
from reach import PlacedNode
from signature import literal_signature, edge_set


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


# Backwards-compatible name: the literal (non-symmetry) signature. Equal for
# two solutions iff they differ only by Sum port order or by the order
# independent wires are placed within a phase.
canonical_signature = literal_signature


def _symmetry_classes(level: Level) -> List[List[str]]:
    """Groups of operation/store node ids that are functionally
    interchangeable: same type for Sum/Subtract/Store, same (type, value) for
    Add. Only groups with 2+ members are returned (a group of one has nothing
    to swap with). Inputs and outputs are never included -- their values are
    guaranteed distinct by the level design, so there's no symmetry there."""
    groups: Dict[tuple, List[str]] = {}
    for op_id, spec in level.operations.items():
        key = ("add", spec.value) if spec.type == "add" else (spec.type,)
        groups.setdefault(key, []).append(op_id)
    return [sorted(ids) for ids in groups.values() if len(ids) >= 2]


def _relabel_solution(solution: Solution, mapping: Dict[str, str]) -> Solution:
    def relabel_node(n: PlacedNode) -> PlacedNode:
        if not mapping:
            return n
        return PlacedNode(
            node_id=mapping.get(n.node_id, n.node_id),
            value=n.value,
            kind=n.kind,
            inputs=tuple(mapping.get(p, p) for p in n.inputs),
        )

    def relabel_built(built):
        return [relabel_node(n) for n in built]

    def relabel_assignment(assignment):
        return {k: mapping.get(v, v) for k, v in assignment.items()}

    new_latches = [
        LatchPhase(
            store_id=mapping.get(l.store_id, l.store_id),
            value=l.value,
            built=relabel_built(l.built),
            assignment=relabel_assignment(l.assignment),
        )
        for l in solution.latches
    ]
    new_final = FinalPhase(
        built=relabel_built(solution.final.built),
        assignment=relabel_assignment(solution.final.assignment),
    )
    return Solution(new_latches, new_final, solution.latch_count)


def _canon(x):
    """Recursively replace every frozenset with a sorted tuple, producing a
    fully order-stable structure. This exists because repr() of a frozenset is
    NOT a reliable canonical form: two content-equal frozensets built via
    different insertion histories can print their elements in a different
    order (their internal hash-table layout isn't determined by content
    alone), even within the same process. That made an earlier version of this
    function pick a different "canonical minimum" among permutation choices
    depending on which raw solution happened to discover it -- so two
    solutions that were genuinely relabeling-equivalent could still fail to
    dedupe, non-deterministically. Once every frozenset in the structure is
    replaced by a sorted tuple (bottom-up, so nested frozensets are already
    stable before their container is sorted), repr() of what remains is a
    tuple of plain strings/ints, which prints identically every time -- so
    sorting by it, and comparing the result, is finally safe."""
    if isinstance(x, frozenset):
        return tuple(sorted((_canon(i) for i in x), key=repr))
    if isinstance(x, tuple):
        return tuple(_canon(i) for i in x)
    return x


def canonical_signature_with_symmetry(level: Level, solution: Solution, classes=None):
    """Like canonical_signature, but additionally treats interchangeable nodes
    (per _symmetry_classes) as equal under any consistent relabeling. Tries
    every combination of permutations across the symmetry classes and picks a
    deterministic minimum, so two solutions that are identical up to relabeling
    interchangeable nodes always land on the exact same signature."""
    if classes is None:
        classes = _symmetry_classes(level)
    if not classes:
        return _canon(literal_signature(solution))

    best = None
    for choice in itertools.product(*(itertools.permutations(cls) for cls in classes)):
        mapping: Dict[str, str] = {}
        for cls, perm in zip(classes, choice):
            mapping.update(dict(zip(cls, perm)))
        relabeled = _relabel_solution(solution, mapping)
        canon = _canon(literal_signature(relabeled))
        if best is None or canon < best:
            best = canon
    return best


def _final_state_and_wiring(solution: Solution):
    """(store contents the final network READS, final wiring) -- deliberately
    excludes every latch phase's own internal structure. Only the last value
    written to each store matters; which route got it there does not.

    Restricted to stores the final network actually reads from. An earlier
    version took every store in `solution.latches`, on the reasoning that
    dead-latch pruning had already removed the rest -- but that is not what
    _prune_dead_latches does. It keeps a latch whose store is read by a later
    LATCH PHASE, which is not the same as being read at the end. A store used
    purely as scratch during a ratchet is legitimately latched, legitimately
    kept, and yet holds a value nobody ever looks at once the level is solved.

    store_4 (I1=3; A1=+2, S1=s, S2=s; O1=11) has this in both its families:

        end {S1: 9, S2: 7}   final network reads only S1  (A1 makes 9+2=11)
        end {S1: 9, S2: 11}  final network reads only S2  (11 wired straight out)

    Including the unused value would make solutions that differ *only* in
    leftover scratch look like different families -- {9,11}, {13,11}, {3,11},
    {5,11} are one solution to a player, since only the 11 is doing anything.
    What is on the board when the player finishes is what they can see being
    used, not every number still sitting in a store.
    """
    final_store_state: Dict[str, int] = {}
    for latch in solution.latches:
        final_store_state[latch.store_id] = latch.value

    read_by_final = {
        producer_id
        for node in solution.final.built
        for producer_id in node.inputs
        if producer_id in final_store_state
    }
    read_by_final |= {
        producer_id
        for producer_id in solution.final.assignment.values()
        if producer_id in final_store_state
    }

    return (
        frozenset(
            (store_id, value)
            for store_id, value in final_store_state.items()
            if store_id in read_by_final
        ),
        edge_set(solution.final.built),
        frozenset(solution.final.assignment.items()),
    )


def family_signature_with_symmetry(level: Level, solution: Solution, classes=None):
    """Like canonical_signature_with_symmetry, but built from
    _final_state_and_wiring instead of the full literal_signature -- i.e. the
    latch-phase routing is irrelevant to the comparison, only the destination
    is. Still tries every relabeling across the interchangeable-node classes
    and picks a deterministic minimum (see _canon for why that has to be done
    via a fully order-stable structure rather than repr() string comparison)."""
    if classes is None:
        classes = _symmetry_classes(level)
    if not classes:
        return _canon(_final_state_and_wiring(solution))

    best = None
    for choice in itertools.product(*(itertools.permutations(cls) for cls in classes)):
        mapping: Dict[str, str] = {}
        for cls, perm in zip(classes, choice):
            mapping.update(dict(zip(cls, perm)))
        relabeled = _relabel_solution(solution, mapping)
        canon = _canon(_final_state_and_wiring(relabeled))
        if best is None or canon < best:
            best = canon
    return best


def _step_count(level: Level, solution: Solution) -> int:
    """Number of actual numbered Connect steps a solution renders to (i.e.
    excluding bracketed auto-sever/latch annotation lines) -- used as the
    tiebreaker after latch count when picking which raw solution best
    represents a family."""
    return sum(1 for line in render_solution(level, solution) if not line.startswith(" "))


def dedupe_families(level: Level, solutions: List[Solution]) -> List[Solution]:
    classes = _symmetry_classes(level)
    groups: Dict[tuple, List[Solution]] = {}
    order: List[tuple] = []
    for s in solutions:
        sig = family_signature_with_symmetry(level, s, classes=classes)
        if sig not in groups:
            groups[sig] = []
            order.append(sig)
        groups[sig].append(s)

    representatives = [
        min(groups[sig], key=lambda s: (s.latch_count, _step_count(level, s)))
        for sig in order
    ]
    representatives.sort(key=lambda s: (s.latch_count, _step_count(level, s)))
    return representatives
