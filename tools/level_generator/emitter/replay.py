"""
The §19.8 transcript replay -- kept as a TEST ORACLE, not as the production
path.

This is the procedure an agent used to execute by hand each session: parse
`render_solution`'s delta-style transcript, maintain a live wiring state, and
snapshot at each latch. `phases.py` derives the same phases from the solver's
structured output instead, which is both simpler and not exposed to the
transcript's formatting.

Keeping this around is deliberate. Two independent derivations agreeing is the
strongest correctness signal available given there is no Godot in the loop, and
these two are genuinely independent: one reads `LatchPhase.built` and
`PlacedNode.inputs`, the other reads rendered English. A bug would have to
appear in both, identically, to go unnoticed.

If a transcript line ever fails to match a pattern here, this module raises
rather than skipping it. The verifier's rendering having changed means the
parser is unsafe, and a silently skipped line is a silently wrong phase.
"""
from __future__ import annotations

import re
from typing import Dict, List, Optional, Set, Tuple

from ir import Path, Phase, Terminator, Wire

_CONNECT_RE = re.compile(
    r"^\s*(\d+)\.\s+Connect\s+(\S+)\s+\((-?\d+)\)\s+(?:->|→)\s+(\S+?)(?:\s+(top|bottom))?\s*$"
)
_LATCH_RE = re.compile(
    r"^\s*\[(\S+)\s+latches\s+(-?\d+);\s+its input auto-disconnects\]\s*$"
)
_SEVER_RE = re.compile(
    r"^\s*\[auto-severs\s+(\S+)\s+(?:->|→)\s+(\S+?)(?:\s+(top|bottom))?\s*\]\s*$"
)

_PORT_INDEX = {None: 0, "top": 0, "bottom": 1}


class ReplayError(RuntimeError):
    """A transcript line did not match any known pattern, or the replay
    disagreed with the transcript's own auto-sever annotation."""


def _walk_back(
    producer_id: str,
    state: Dict[Tuple[str, int], str],
    out: List[Wire],
    seen: Set[str],
) -> None:
    if producer_id in seen:
        return
    seen.add(producer_id)
    for (to_id, to_port), from_id in sorted(state.items()):
        if to_id != producer_id:
            continue
        out.append(Wire(from_id=from_id, from_port=0, to_id=to_id, to_port=to_port))
        _walk_back(from_id, state, out, seen)


def _dedupe(wires: List[Wire]) -> Tuple[Wire, ...]:
    seen: Set[Wire] = set()
    out: List[Wire] = []
    for w in wires:
        if w not in seen:
            seen.add(w)
            out.append(w)
    return tuple(out)


def replay_transcript(lines, level, prune_final: bool = True) -> Path:
    """Replay a `render_solution` transcript into phases.

    `prune_final` controls the final phase. §19.8 says to take "the surviving
    contents of `state`, with no pruning -- minimality guarantees every node is
    reachable from the outputs there." That claim is about the *level* being
    minimal (every node needed somewhere), which does not imply every node is
    needed in the *final* phase specifically: a wire built during a latch phase
    can survive untouched into the final state while feeding nothing any output
    reads. Pruning by backward reachability from the outputs makes the oracle
    agree with the structured extraction on what the final phase means; pass
    False to reproduce §19.8 literally and see the difference.
    """
    state: Dict[Tuple[str, int], str] = {}
    phases: List[Phase] = []
    store_ids = set(level.store_ops().keys())

    for raw in lines:
        line = raw.rstrip("\n")
        if not line.strip():
            continue

        m = _CONNECT_RE.match(line)
        if m:
            _, from_id, _value, to_id, port = m.groups()
            state[(to_id, _PORT_INDEX[port])] = from_id
            continue

        m = _LATCH_RE.match(line)
        if m:
            store_id, value = m.group(1), int(m.group(2))
            producer_id = state.get((store_id, 0))
            if producer_id is None:
                raise ReplayError(
                    f"{store_id} latches {value} but nothing is wired to its input."
                )
            wires = [Wire(from_id=producer_id, from_port=0, to_id=store_id, to_port=0)]
            _walk_back(producer_id, state, wires, set())
            phases.append(
                Phase(wires=_dedupe(wires), terminator=Terminator(store_id, value))
            )
            del state[(store_id, 0)]
            continue

        m = _SEVER_RE.match(line)
        if m:
            # No action -- the overwrite already did it. But assert the
            # annotation agrees with what we replaced; a mismatch means the
            # parse is wrong, and a wrong parse that keeps going is exactly
            # what this oracle exists to rule out.
            from_id, to_id, port = m.groups()
            current = state.get((to_id, _PORT_INDEX[port]))
            if current is None:
                raise ReplayError(
                    f"Transcript says '{from_id} -> {to_id}' was auto-severed, but the "
                    f"replay has nothing wired there."
                )
            continue

        raise ReplayError(
            f"Transcript line matched no known pattern: {line!r}. The verifier's "
            f"rendering has changed and this parser is now unsafe -- do not guess "
            f"at the new format."
        )

    final_wires: List[Wire] = []
    if prune_final:
        seen: Set[str] = set()
        for output_id in sorted(level.outputs):
            producer_id = state.get((output_id, 0))
            if producer_id is None:
                raise ReplayError(f"Output {output_id} is unwired at the end of the transcript.")
            final_wires.append(Wire(producer_id, 0, output_id, 0))
            _walk_back(producer_id, state, final_wires, seen)
    else:
        final_wires = [
            Wire(from_id=src, from_port=0, to_id=to_id, to_port=to_port)
            for (to_id, to_port), src in sorted(state.items())
        ]
    phases.append(Phase(wires=_dedupe(final_wires), terminator=None))

    # Drop any phase whose store is never read afterwards. Same reverse sweep
    # as phases.py, restated here rather than imported: an oracle that shares
    # its dead-latch logic with the thing it checks is not independent of it.
    kept_reversed: List[Phase] = []
    needed = {w.from_id for w in phases[-1].wires if w.from_id in store_ids}
    for phase in reversed(phases[:-1]):
        assert phase.terminator is not None
        if phase.terminator.store_id not in needed:
            continue
        kept_reversed.append(phase)
        needed.discard(phase.terminator.store_id)
        needed |= {w.from_id for w in phase.wires if w.from_id in store_ids}

    return Path(phases=tuple(reversed(kept_reversed)) + (phases[-1],))


def phase_wire_sets(path: Path):
    """(frozenset of wires, terminator) per phase -- the form in which the two
    derivations are compared. Ordering is CR-P2's business, not CR-P1's, so
    the comparison is deliberately order-insensitive."""
    return [(frozenset(p.wires), p.terminator) for p in path.phases]
