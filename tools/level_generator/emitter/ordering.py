"""
CR-P2 -- canonical intra-phase ordering.

Ordering does not affect hint-system correctness: a phase is evaluated as a
set, and a wire made then replaced inside one phase was wasted motion either
way. It affects the *player* directly, because hints are offered in list order.
That is why this is its own module rather than an incidental sort at
serialisation time.

The rule, from §19.9:

    Walk the phase's target nodes in topological order -- a node comes after
    every node that feeds it. On reaching a node, emit all of its input wires
    contiguously, ascending to_port.

Two properties follow, and both were violated by hand-transcription before:

  1. A node's input wires precede any wire leaving that node. Wiring
     `M1 -> P1` before M1 has inputs shows the player a hint that produces
     nothing.
  2. A multi-input node's input wires are contiguous. Written per-node rather
     than as "two steps", so it survives node types with more than two inputs.

Ties among simultaneously-ready nodes break by operations-array order, then
outputs-array order -- which is why this needs the `Layout` and not just the
phase.
"""
from __future__ import annotations

from typing import Dict, List, Sequence, Set

from ir import Layout, Path, Phase, Wire


class OrderingError(RuntimeError):
    """No canonical order could be produced, or the produced order violates an
    invariant it is supposed to guarantee.

    Always fatal. Falling back to insertion order would hand the player a hint
    sequence that asks them to wire a node's output before that node has a
    value -- the exact failure this module exists to prevent -- while looking
    like it worked.
    """


def _tiebreak_rank(layout: Layout) -> Dict[str, int]:
    """Node id -> tie-break rank: operations-array order, then outputs-array
    order. Outputs are sinks and therefore land last anyway; ranking them
    explicitly after operations makes that a guarantee rather than a
    coincidence of the graph shape.

    Inputs never appear as targets, so they are not ranked.
    """
    rank: Dict[str, int] = {}
    for i, entry in enumerate(layout.operations):
        rank[entry.node_id] = i
    offset = len(layout.operations)
    for i, entry in enumerate(layout.outputs):
        rank[entry.node_id] = offset + i
    return rank


def order_phase(phase: Phase, layout: Layout, phase_label: str = "") -> Phase:
    """Return `phase` with its wires in canonical order."""
    inbound: Dict[str, Dict[int, Wire]] = {}
    for w in phase.wires:
        ports = inbound.setdefault(w.to_id, {})
        if w.to_port in ports:
            raise OrderingError(
                f"{phase_label}: {w.to_id} port {w.to_port} has two wires "
                f"({ports[w.to_port].from_id!r}, {w.from_id!r}). A port holds one wire."
            )
        ports[w.to_port] = w

    targets: Set[str] = set(inbound)
    rank = _tiebreak_rank(layout)
    for node_id in targets:
        if node_id not in rank:
            raise OrderingError(
                f"{phase_label}: {node_id!r} is wired into but is not an operation "
                f"or output of this level, so it has no tie-break rank."
            )

    # A target depends only on feeding nodes that are themselves targets of
    # this phase. Sources (level inputs, stores holding pre-phase values) are
    # available from the start.
    unmet: Dict[str, Set[str]] = {
        node_id: {w.from_id for w in ports.values() if w.from_id in targets}
        for node_id, ports in inbound.items()
    }

    ordered: List[Wire] = []
    emitted: Set[str] = set()
    while unmet:
        ready = [n for n, deps in unmet.items() if not (deps - emitted)]
        if not ready:
            # The phase's wiring is always a DAG -- GraphCanvas blocks cycles --
            # so a topological order always exists. If we get here the IR is
            # malformed, and inventing an order would bury that.
            raise OrderingError(
                f"{phase_label}: no topological order exists over targets "
                f"{sorted(unmet)}. The phase wiring contains a cycle, which "
                f"GraphCanvas would have blocked -- the IR is wrong."
            )
        chosen = min(ready, key=lambda n: rank[n])
        # All of this node's input wires, contiguously, ascending port.
        ordered.extend(inbound[chosen][p] for p in sorted(inbound[chosen]))
        emitted.add(chosen)
        del unmet[chosen]

    result = phase.with_wires(ordered)
    _assert_invariants(result, layout, phase_label)
    return result


def _assert_invariants(phase: Phase, layout: Layout, phase_label: str) -> None:
    """Re-check, from the produced sequence alone, the properties the algorithm
    is supposed to guarantee. Cheap, and it catches a regression in the walk
    above rather than three stages later in a `.tres` nobody can read."""
    seen_complete: Set[str] = set()
    index = 0
    while index < len(phase.wires):
        node_id = phase.wires[index].to_id
        run_end = index
        while run_end < len(phase.wires) and phase.wires[run_end].to_id == node_id:
            run_end += 1
        run = phase.wires[index:run_end]

        if node_id in seen_complete:
            raise OrderingError(
                f"{phase_label}: {node_id}'s input wires are not contiguous -- they "
                f"appear in two separate runs. A multi-input node must be hinted as "
                f"one group (§19.9 rule 2)."
            )
        ports = [w.to_port for w in run]
        if ports != sorted(ports):
            raise OrderingError(
                f"{phase_label}: {node_id}'s input wires are not in ascending port "
                f"order (got {ports})."
            )
        for w in run:
            if w.from_id not in seen_complete and any(
                other.to_id == w.from_id for other in phase.wires
            ):
                raise OrderingError(
                    f"{phase_label}: {w} appears before {w.from_id} has all of its own "
                    f"inputs. A node's input wires must precede any wire leaving it "
                    f"(§19.9 rule 1)."
                )
        seen_complete.add(node_id)
        index = run_end

    if not phase.is_final:
        assert phase.terminator is not None
        last = phase.wires[-1] if phase.wires else None
        if last is None:
            raise OrderingError(f"{phase_label}: phase has no connections.")
        # The latch connection is a sink, so a topological order places it last
        # without special-casing. Assert it regardless -- if it ever stops being
        # true, the hint system offers the latch wire early and the player
        # latches whatever garbage the producer currently holds.
        if last.to_id != phase.terminator.store_id:
            raise OrderingError(
                f"{phase_label}: last connection targets {last.to_id!r}, but the "
                f"terminator latches {phase.terminator.store_id!r}. The latch "
                f"connection must be last in its phase (§19.9 rule 1)."
            )
    else:
        output_ids = {e.node_id for e in layout.outputs}
        targeted = [w.to_id for w in phase.wires]
        first_output = next((i for i, t in enumerate(targeted) if t in output_ids), None)
        if first_output is not None and any(
            t not in output_ids for t in targeted[first_output:]
        ):
            raise OrderingError(
                f"{phase_label}: a non-output wire follows an output-targeted wire. "
                f"Outputs are sinks and must all be last in the final phase."
            )


def order_path(path: Path, layout: Layout, path_label: str = "path") -> Path:
    return Path(
        phases=tuple(
            order_phase(phase, layout, f"{path_label} phase {i}")
            for i, phase in enumerate(path.phases)
        )
    )


def order_paths(paths: Sequence[Path], layout: Layout, level_name: str = "") -> List[Path]:
    prefix = f"{level_name} " if level_name else ""
    return [
        order_path(p, layout, f"{prefix}path {i}") for i, p in enumerate(paths)
    ]
