"""
CR-P1 -- phase extraction from structured solver output.

Consumes the solver's *structured* result (`Solution`, `LatchPhase`,
`FinalPhase`, `PlacedNode`, re-exported through `level_verifier/api.py`) and
produces the neutral IR in `ir.py`.

WHY STRUCTURED AND NOT THE TRANSCRIPT
-------------------------------------
`render_solution` in notation.py emits *deltas*: it suppresses any wire already
correct from an earlier phase. A phase needs a *snapshot* -- every wire live at
its latch. Reconstructing snapshots by re-parsing delta text is possible (that
is what §19.8's replay does, and what an agent used to do by hand each session)
but it is exactly the error-prone step this pipeline exists to eliminate.
`LatchPhase.built` plus `PlacedNode.inputs` gives the network directly.

The replay remains, in `replay.py`, purely as a test oracle. Two independent
derivations agreeing is the strongest correctness signal available given there
is no Godot in the loop.

Per §1 of the agent instructions, this module reads nothing under
`level_verifier/` except `api.py`.
"""
from __future__ import annotations

from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

from ir import Path, Phase, Terminator, Wire


class PhaseExtractionError(RuntimeError):
    """Extraction hit something it will not guess at. Always fatal."""


# `PlacedNode.kind` -> number of input ports. Ports are positional: index 0 is
# top / the sole input, index 1 is bottom (§19.6). SubtractNode computes
# inputs[0] - inputs[1], so this order is load-bearing.
_ARITY = {"add": 1, "sum": 2, "subtract": 2}


def _port_count(kind: str) -> int:
    try:
        return _ARITY[kind]
    except KeyError:
        raise PhaseExtractionError(
            f"PlacedNode kind {kind!r} has no known arity. The verifier's node "
            f"vocabulary has changed; extraction is unsafe until this is updated."
        ) from None


def _walk_back(
    producer_id: str,
    built_by_id: Dict[str, object],
    out: List[Wire],
    seen: Set[str],
) -> None:
    """Collect every wire transitively feeding `producer_id`.

    Terminates at sources -- level inputs, and stores holding their pre-phase
    values -- which are simply ids absent from `built_by_id`.

    The backward walk is not optional. A wire can be live at a latch while
    feeding nothing that matters to it; carrying it into the phase would send
    the player off to build something the phase does not need. In challenge_1
    family 1, `I1 -> P1 top` is live when S1 latches and is correctly kept, but
    by S2's latch P1 is fed from M1 instead and the stale pair must be dropped.
    """
    if producer_id in seen:
        return
    seen.add(producer_id)
    node = built_by_id.get(producer_id)
    if node is None:
        return  # a source: level input, or a store holding a pre-phase value
    expected = _port_count(node.kind)
    if len(node.inputs) != expected:
        raise PhaseExtractionError(
            f"Node {node.node_id!r} of kind {node.kind!r} has {len(node.inputs)} "
            f"inputs; expected {expected}."
        )
    for port, upstream_id in enumerate(node.inputs):
        out.append(Wire(from_id=upstream_id, from_port=0, to_id=node.node_id, to_port=port))
        _walk_back(upstream_id, built_by_id, out, seen)


def _reachable_wires(
    roots: Sequence[Tuple[str, str, int]],
    built: Iterable,
) -> Tuple[Wire, ...]:
    """Wires reachable backwards from each `(producer_id, sink_id, sink_port)`
    root, plus the root wires themselves.

    Deduplicated while preserving first-seen order. Order is not meaningful
    here -- a phase is a set until CR-P2 orders it -- but a stable order keeps
    intermediate dumps diffable.
    """
    built_by_id = {n.node_id: n for n in built}
    wires: List[Wire] = []
    seen: Set[str] = set()
    for producer_id, sink_id, sink_port in roots:
        wires.append(Wire(from_id=producer_id, from_port=0, to_id=sink_id, to_port=sink_port))
        _walk_back(producer_id, built_by_id, wires, seen)

    deduped: List[Wire] = []
    known: Set[Wire] = set()
    for w in wires:
        if w not in known:
            known.add(w)
            deduped.append(w)
    return tuple(deduped)


def _stores_read(wires: Iterable[Wire], store_ids: Set[str]) -> Set[str]:
    return {w.from_id for w in wires if w.from_id in store_ids}


def _drop_dead_latches(phases: List[Phase], store_ids: Set[str]) -> List[Phase]:
    """Drop any latch phase whose store is never subsequently read.

    Reverse sweep rather than a forward filter, so cascades resolve in one
    pass: if phase 1 is dead and phase 0 exists only to feed it, phase 0 goes
    too. A forward filter would keep phase 0, having already decided phase 1
    was a reader before discovering phase 1 was itself dead.
    """
    if not phases:
        return []
    final = phases[-1]
    if not final.is_final:
        raise PhaseExtractionError("Last phase must be the final phase (no terminator).")

    needed = _stores_read(final.wires, store_ids)
    kept_reversed: List[Phase] = []
    for phase in reversed(phases[:-1]):
        assert phase.terminator is not None
        store_id = phase.terminator.store_id
        if store_id not in needed:
            continue  # dead: nothing downstream ever reads this value
        kept_reversed.append(phase)
        needed.discard(store_id)
        needed |= _stores_read(phase.wires, store_ids)

    return list(reversed(kept_reversed)) + [final]


def extract_path(level, solution) -> Path:
    """One `Solution` -> one `Path` of phases.

    For each `LatchPhase`: the wires reachable backwards from
    `assignment['_latch']` through `built`, plus the latch wire itself, closed
    by a `(store_id, value)` terminator.

    For the `FinalPhase`: the wires reachable backwards from every entry in
    `assignment`, unpruned beyond that reachability, with no terminator.
    """
    store_ids = set(level.store_ops().keys())
    phases: List[Phase] = []

    for latch in solution.latches:
        try:
            producer_id = latch.assignment["_latch"]
        except KeyError:
            raise PhaseExtractionError(
                f"LatchPhase for {latch.store_id} has no '_latch' assignment."
            ) from None
        if latch.store_id not in store_ids:
            raise PhaseExtractionError(
                f"LatchPhase names {latch.store_id!r}, which is not a store in {level.name}."
            )
        if producer_id == latch.store_id:
            raise PhaseExtractionError(
                f"{latch.store_id} would latch from itself -- that is the cycle rule "
                f"violated upstream, not something to encode."
            )
        wires = _reachable_wires(
            roots=[(producer_id, latch.store_id, 0)],
            built=latch.built,
        )
        phases.append(
            Phase(wires=wires, terminator=Terminator(store_id=latch.store_id, value=latch.value))
        )

    # Outputs sorted by id so extraction is deterministic; CR-P2 re-orders by
    # the outputs array anyway, but a stable pre-order keeps the two
    # derivations in the cross-check comparable as sequences, not just as sets.
    final_roots = [
        (producer_id, output_id, 0)
        for output_id, producer_id in sorted(solution.final.assignment.items())
    ]
    missing = set(solution.final.assignment) - set(level.outputs)
    if missing:
        raise PhaseExtractionError(
            f"Final phase assigns to {sorted(missing)}, which are not outputs of {level.name}."
        )
    if set(solution.final.assignment) != set(level.outputs):
        unassigned = set(level.outputs) - set(solution.final.assignment)
        raise PhaseExtractionError(
            f"Final phase leaves outputs {sorted(unassigned)} unassigned."
        )
    phases.append(Phase(wires=_reachable_wires(final_roots, solution.final.built), terminator=None))

    return Path(phases=tuple(_drop_dead_latches(phases, store_ids)))


def extract_paths(level, solutions: Sequence) -> List[Path]:
    return [extract_path(level, s) for s in solutions]


# --------------------------------------------------------------------------
# Evaluation -- shared by the arithmetic checks in validate.py and by the
# cross-check in the test corpus.
# --------------------------------------------------------------------------

def phase_source_values(level, path: Path, phase_index: int) -> Dict[str, int]:
    """Values available as sources at the start of `phase_index`: the level's
    inputs, plus every store holding the value its last preceding terminator
    latched.

    This mirrors the solver's `sources_for_state` but is computed from the IR,
    so it stays valid after dead-latch pruning has removed phases the solver
    originally produced.
    """
    values: Dict[str, int] = dict(level.inputs)
    for phase in path.phases[:phase_index]:
        if phase.terminator is not None:
            values[phase.terminator.store_id] = phase.terminator.value
    return values


class EvaluationError(RuntimeError):
    """A phase's wiring could not be evaluated -- unwired port, cycle, or an
    unknown source. Always a transcription bug, never a level bug."""


class PhaseEval:
    """Result of evaluating one phase.

    `values` holds each node's live output. `latched` holds what each store
    *would capture*, kept deliberately separate: a store's live value during a
    phase is whatever it held coming in, not the number arriving at its input.
    Writing the captured value into `values` would make evaluation
    order-dependent for any phase that both reads a store and latches it.

    The solver never produces such a phase -- it excludes a store from its own
    candidate sources -- but relying on that silently is how order-dependent
    bugs get in. `assert_no_read_and_latch` checks it instead.
    """

    __slots__ = ("values", "latched")

    def __init__(self, values: Dict[str, int], latched: Dict[str, int]):
        self.values = values
        self.latched = latched


def evaluate_phase(level, path: Path, phase_index: int) -> PhaseEval:
    """Evaluate a phase's wiring.

    Raises rather than returning partial results: a node left partially wired
    is exactly what §19.13 check 2 is looking for, and swallowing it here would
    hide it.
    """
    phase = path.phases[phase_index]
    store_ids = set(level.store_ops().keys())
    values = phase_source_values(level, path, phase_index)
    latched: Dict[str, int] = {}

    inbound: Dict[str, Dict[int, str]] = {}
    for w in phase.wires:
        ports = inbound.setdefault(w.to_id, {})
        if w.to_port in ports and ports[w.to_port] != w.from_id:
            raise EvaluationError(
                f"{level.name} phase {phase_index}: two different sources wired to "
                f"{w.to_id} port {w.to_port} ({ports[w.to_port]!r} and {w.from_id!r}). "
                f"A port holds one wire; the second would auto-sever the first."
            )
        ports[w.to_port] = w.from_id

    latched_stores = set(inbound) & store_ids
    read_stores = {w.from_id for w in phase.wires if w.from_id in store_ids}
    both = latched_stores & read_stores
    if both:
        raise EvaluationError(
            f"{level.name} phase {phase_index}: store(s) {sorted(both)} are both read "
            f"and latched within one phase. Evaluation is ambiguous -- the store's live "
            f"value and its captured value are different numbers at the same instant."
        )

    # Iterate to fixpoint. The wiring is always a DAG (GraphCanvas blocks
    # cycles), so this terminates in at most len(inbound) rounds; if it does
    # not, something has produced a cycle and we say so rather than looping.
    pending = dict(inbound)
    for _ in range(len(inbound) + 1):
        if not pending:
            break
        progressed = False
        for node_id in list(pending):
            ports = pending[node_id]
            if not all(src in values for src in ports.values()):
                continue
            args = [ports[p] for p in sorted(ports)]
            result = _apply(level, node_id, [values[a] for a in args], phase_index)
            if node_id in store_ids:
                latched[node_id] = result
            else:
                values[node_id] = result
            del pending[node_id]
            progressed = True
        if not progressed:
            break

    if pending:
        stuck = sorted(pending)
        raise EvaluationError(
            f"{level.name} phase {phase_index}: could not evaluate {stuck} -- either "
            f"an input is unwired or the wiring contains a cycle."
        )
    return PhaseEval(values=values, latched=latched)


def _apply(level, node_id: str, args: List[int], phase_index: int) -> int:
    if node_id in level.outputs:
        if len(args) != 1:
            raise EvaluationError(f"Output {node_id} has {len(args)} inputs; expected 1.")
        return args[0]
    spec = level.operations.get(node_id)
    if spec is None:
        raise EvaluationError(
            f"Phase {phase_index} wires into {node_id!r}, which is not an operation "
            f"or output of {level.name}."
        )
    if spec.type == "add":
        _expect(node_id, args, 1)
        return args[0] + spec.value
    if spec.type == "sum":
        _expect(node_id, args, 2)
        return args[0] + args[1]
    if spec.type == "subtract":
        _expect(node_id, args, 2)
        return args[0] - args[1]
    if spec.type == "store":
        _expect(node_id, args, 1)
        return args[0]  # the value being captured, not the store's held value
    raise EvaluationError(f"Unknown operation type {spec.type!r} on {node_id!r}.")


def _expect(node_id: str, args: List[int], n: int) -> None:
    if len(args) != n:
        raise EvaluationError(
            f"{node_id} is wired with {len(args)} input(s); it takes {n}. "
            f"A partially wired node is a transcription bug."
        )
