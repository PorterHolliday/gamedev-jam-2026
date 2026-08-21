"""
The emitter's intermediate representation.

Deliberately neutral: it names nodes by their *generator* id (`P1`, `S2`, `I1`)
and carries Godot's `(NodeType, slot)` alongside, but it depends on neither the
solver's dataclasses nor Godot's resource format. Every stage after CR-P1
consumes this and nothing else, which is what lets the transcript-replay oracle
in the test corpus be compared against the structured extraction directly.

Ports are integers throughout: 0 = top / sole input, 1 = bottom (§19.6). The
solver's "top"/"bottom" strings are converted at the boundary in phases.py, so
no stage downstream of extraction ever sees a port name.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Optional, Tuple


@dataclass(frozen=True)
class Wire:
    """One connection. `from_port` is always 0 -- every node type in play has a
    single output port (§19.6)."""
    from_id: str
    from_port: int
    to_id: str
    to_port: int

    def __str__(self) -> str:
        port = {0: " top", 1: " bottom"}.get(self.to_port, f" port{self.to_port}")
        return f"{self.from_id} -> {self.to_id}{port}"


@dataclass(frozen=True)
class Terminator:
    """The latch that closes a phase: which store, and to what value."""
    store_id: str
    value: int

    def __str__(self) -> str:
        return f"{self.store_id}={self.value}"


@dataclass(frozen=True)
class Phase:
    """A set of wires that must all be live at the instant of one latch.

    `wires` is a *snapshot*, not a delta -- every wire the terminator's value
    depends on, including ones placed several phases earlier and never touched
    since. See §19.8 "Why snapshots and not the steps since the last latch".

    Unordered as produced by CR-P1; canonically ordered by CR-P2. Both are the
    same type because ordering is a pure permutation -- nothing else changes.
    """
    wires: Tuple[Wire, ...]
    terminator: Optional[Terminator]

    @property
    def is_final(self) -> bool:
        return self.terminator is None

    def with_wires(self, wires) -> "Phase":
        return Phase(wires=tuple(wires), terminator=self.terminator)


@dataclass(frozen=True)
class Path:
    """One journey: ordered phases, the last of which has no terminator."""
    phases: Tuple[Phase, ...]

    @property
    def latch_sequence(self) -> Tuple[Terminator, ...]:
        return tuple(p.terminator for p in self.phases if p.terminator is not None)


@dataclass(frozen=True)
class NodeEntry:
    """One `GraphNodeData` in one of the three arrays.

    `slot` is the 0-based index among nodes of the same NodeType in the final,
    ordered array (§19.5). It is set by layout.build_layout and by nothing
    else -- see the sequencing hazard note there.
    """
    node_id: str            # generator id, e.g. "P1"
    node_type: str          # NodeType name, e.g. "SUM"
    slot: int
    value: Optional[int]    # authored value, or None for SUM/SUBTRACT/STORE

    @property
    def ref(self) -> Tuple[str, int]:
        return (self.node_type, self.slot)


@dataclass(frozen=True)
class Layout:
    """The three ordered arrays plus the generator-id -> (type, slot) map.

    Returned as one object on purpose: a map built against a differently
    ordered array points every hint at the wrong node and nothing detects it
    short of playing the level (CR-P8, "Sequencing hazard").
    """
    inputs: Tuple[NodeEntry, ...]
    operations: Tuple[NodeEntry, ...]
    outputs: Tuple[NodeEntry, ...]
    by_id: Dict[str, NodeEntry]

    def entry(self, node_id: str) -> NodeEntry:
        try:
            return self.by_id[node_id]
        except KeyError:
            raise KeyError(
                f"Node id {node_id!r} is referenced by the solution but is not in "
                f"the level's node arrays."
            ) from None

    def ref(self, node_id: str) -> Tuple[str, int]:
        return self.entry(node_id).ref

    @property
    def all_entries(self) -> Tuple[NodeEntry, ...]:
        return self.inputs + self.operations + self.outputs


@dataclass(frozen=True)
class LevelIR:
    """Everything needed to serialise a level, and nothing Godot-specific."""
    name: str
    layout: Layout
    paths: Tuple[Path, ...]
    # Provenance, carried through for the §19.14 report only.
    family_count: int = 0
    bound: Tuple[int, int] = (0, 0)
    max_latches: int = 0
