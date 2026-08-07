"""
CR-P3 -- structural validation.

Every check in §19.13, as an assertion over the intermediate representation,
run before serialisation. A failure aborts emission. Nothing here warns and
continues: a `.tres` that loads cleanly and points every hint at the wrong node
is worse than no `.tres` at all, because nothing detects it short of playing
the level.

Failures name the level, the path, and the phase, because "check 5 failed" from
a batch run over twenty-five levels is not actionable.

ON CHECK 5
----------
The required-store-state analysis is the same one the game performs at runtime
(HINT_SYSTEM_PHASE_CHANGE_REQUESTS.md CR-1). It is implemented here *from that
specification*, not by porting the GDScript. Two independent implementations
agreeing is the point; a port would agree with itself and prove nothing.

ON CHECK 6
----------
Topological ordering is re-derived here from the emitted wire sequence alone,
deliberately not by calling into ordering.py. A check that shares code with the
thing it checks only confirms the code is self-consistent.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Set, Tuple

from ir import Layout, LevelIR, Path, Phase
from phases import EvaluationError, evaluate_phase
from project import Project


@dataclass(frozen=True)
class DisplayRanges:
    """§9 value ranges. Values outside these overflow the node's bounding box
    in game.

    Configurable, because §9 describes them as three independently
    configurable flags with these defaults -- not as constants. A level
    generated under a deliberately widened `--output-range` is legitimate; a
    level that drifts outside the default range unnoticed is not. Defaulting
    to §9's defaults keeps the check firing unless someone widens it on
    purpose, and the failure message names the flag so the choice is recorded
    rather than guessed at.

    Add values are tighter on the positive side because they render with a
    leading `+`, so a double-digit value overflows in either direction.
    """
    # §9's three display ranges. Kept separate rather than merged: inputs and
    # outputs are drawn in differently sized nodes, so they do not share a
    # range, and widening one must not quietly widen the other.
    #
    # These are the DISPLAY ranges, which are authoritative. generate.py's
    # flag defaults are (-9,20) / (-9,20) / (-9,9) and do not match -- see §9.
    # A level sampled at the generator's defaults can carry an input of 20 and
    # will be rejected here, which is the intended direction of failure.
    input: Tuple[int, int] = (-9, 9)
    output: Tuple[int, int] = (-20, 20)
    add_value: Tuple[int, int] = (-9, 9)

    def for_type(self, node_type: str) -> Tuple[int, int]:
        return {
            "INPUT": self.input,
            "OUTPUT": self.output,
            "ADD_VALUE": self.add_value,
        }[node_type]


DEFAULT_RANGES = DisplayRanges()

INPUT_RANGE = DEFAULT_RANGES.input
OUTPUT_RANGE = DEFAULT_RANGES.output
ADD_VALUE_RANGE = DEFAULT_RANGES.add_value


class ValidationError(RuntimeError):
    """An emitted level violates a structural invariant. Always fatal."""


def _fail(level_name: str, check: str, detail: str) -> None:
    raise ValidationError(f"{level_name}: [{check}] {detail}")


# --------------------------------------------------------------------------
# Required store state (shared by check 5; also the reference implementation
# the game side is expected to agree with)
# --------------------------------------------------------------------------

def required_state(path: Path, store_slot_of: Dict[str, int], phase_index: int) -> Dict[int, int]:
    """Map of store slot -> value that must currently hold for `phase_index` to
    be the player's position.

    Implemented from HINT CR-1's specification:

      1. last_latch(s, k) = the value of the last terminator on store s among
         phases < k. No such terminator means s contributes nothing.
      2. s is LIVE at k iff, scanning phases j = k, k+1, ... n in order:
           - if phase j reads s (a wire whose source is s), s is live -- stop;
           - otherwise if phase j's terminator latches s, s is dead -- stop;
           - otherwise continue. Falling off the end means dead.
      3. s appears with value last_latch(s, k) iff it has a last latch and is
         live at k.

    The read check MUST precede the re-latch check *within the same phase*: a
    phase may both read a store and re-latch it. In the CR's worked example,
    phase 1 reads S1 into M1 and latches S2, while phase 2 re-latches S1
    without reading it -- which is why S1 is required at phase 1 and absent at
    phase 2.

    required_state(0) is always empty: nothing has latched yet.
    """
    state: Dict[int, int] = {}
    for store_id, slot in store_slot_of.items():
        last: Optional[int] = None
        for phase in path.phases[:phase_index]:
            if phase.terminator is not None and phase.terminator.store_id == store_id:
                last = phase.terminator.value
        if last is None:
            continue

        live = False
        for phase in path.phases[phase_index:]:
            if any(w.from_id == store_id for w in phase.wires):
                live = True
                break
            if phase.terminator is not None and phase.terminator.store_id == store_id:
                break
        if live:
            state[slot] = last
    return state


def required_states(path: Path, store_slot_of: Dict[str, int]) -> List[Dict[int, int]]:
    return [required_state(path, store_slot_of, k) for k in range(len(path.phases))]


# --------------------------------------------------------------------------
# The nine checks
# --------------------------------------------------------------------------

def _check_arithmetic(level, level_ir: LevelIR, path: Path, path_index: int) -> None:
    """Check 1. Non-final phases: evaluating the wiring gives the terminator's
    value at the latch producer. Final phase: every output receives its
    declared target, and no node is partially wired (evaluate_phase raises on
    that rather than returning a partial result)."""
    name = level_ir.name
    for k, phase in enumerate(path.phases):
        where = f"path {path_index} phase {k}"
        try:
            ev = evaluate_phase(level, path, k)
        except EvaluationError as exc:
            _fail(name, "1 arithmetic", f"{where}: {exc}")

        if phase.terminator is not None:
            store_id = phase.terminator.store_id
            got = ev.latched.get(store_id)
            if got is None:
                _fail(name, "1 arithmetic",
                      f"{where}: nothing is wired into {store_id}, but the terminator "
                      f"says it latches {phase.terminator.value}.")
            if got != phase.terminator.value:
                _fail(name, "1 arithmetic",
                      f"{where}: {store_id} would latch {got}, but the terminator says "
                      f"{phase.terminator.value}.")
        else:
            for entry in level_ir.layout.outputs:
                got = ev.values.get(entry.node_id)
                if got is None:
                    _fail(name, "1 arithmetic",
                          f"{where}: output {entry.node_id} is not wired.")
                if got != entry.value:
                    _fail(name, "1 arithmetic",
                          f"{where}: output {entry.node_id} receives {got}, target is "
                          f"{entry.value}.")


def _check_latch_placement(level_ir: LevelIR, path: Path, path_index: int) -> None:
    """Check 2. The last connection of each non-final phase targets the store
    its terminator names, and no other connection in that phase targets it.

    The second half matters as much as the first: a second wire into the store
    earlier in the phase would latch a value and auto-sever before the
    intended one ever arrives.
    """
    for k, phase in enumerate(path.phases):
        if phase.is_final:
            continue
        assert phase.terminator is not None
        store_id = phase.terminator.store_id
        where = f"path {path_index} phase {k}"
        if not phase.wires:
            continue  # check 3's business
        if phase.wires[-1].to_id != store_id:
            _fail(level_ir.name, "2 latch placement",
                  f"{where}: last connection targets {phase.wires[-1].to_id!r}, "
                  f"terminator latches {store_id!r}.")
        earlier = [w for w in phase.wires[:-1] if w.to_id == store_id]
        if earlier:
            _fail(level_ir.name, "2 latch placement",
                  f"{where}: {len(earlier)} earlier connection(s) also target "
                  f"{store_id!r} ({[str(w) for w in earlier]}). Each would latch and "
                  f"auto-sever before the intended one arrives.")


def _check_no_empty_phase(level_ir: LevelIR, path: Path, path_index: int) -> None:
    """Check 3. Every terminator is preceded by at least one connection in its
    own phase."""
    for k, phase in enumerate(path.phases):
        if not phase.wires:
            _fail(level_ir.name, "3 empty phase",
                  f"path {path_index} phase {k} has no connections"
                  + (f" but terminates in {phase.terminator}." if phase.terminator else "."))


def _check_no_dead_latch(level_ir: LevelIR, path: Path, path_index: int) -> None:
    """Check 4. Every terminator's store is read in some later phase or in the
    final phase. A latch nothing ever reads is wasted authoring."""
    for k, phase in enumerate(path.phases):
        if phase.terminator is None:
            continue
        store_id = phase.terminator.store_id
        if not any(
            any(w.from_id == store_id for w in later.wires)
            for later in path.phases[k + 1:]
        ):
            _fail(level_ir.name, "4 dead latch",
                  f"path {path_index} phase {k} latches {phase.terminator}, but no "
                  f"later phase reads {store_id}.")


def _check_distinct_required_states(
    level_ir: LevelIR, path: Path, path_index: int, store_slot_of: Dict[str, int]
) -> None:
    """Check 5. No two phases in a path may have identical required states.

    The cursor is `max k` over matching required states, not the longest
    matching prefix -- so a collision does not produce a visible error, it
    makes the hint system silently skip the earlier phase's work.
    """
    states = required_states(path, store_slot_of)
    seen: Dict[Tuple[Tuple[int, int], ...], int] = {}
    for k, state in enumerate(states):
        key = tuple(sorted(state.items()))
        if key in seen:
            _fail(level_ir.name, "5 duplicate required state",
                  f"path {path_index} phases {seen[key]} and {k} both require "
                  f"{dict(key) or '{}'}. The cursor takes the higher index, so phase "
                  f"{seen[key]}'s work would be silently skipped.")
        seen[key] = k


def _check_topological_order(level_ir: LevelIR, path: Path, path_index: int) -> None:
    """Check 6. Re-derived from the emitted sequence alone -- deliberately not
    by calling ordering.py.

    Asserts, per phase: a multi-input node's wires are contiguous and in
    ascending port order, and no wire leaves a node before that node's own
    input wires have all appeared.
    """
    output_ids = {e.node_id for e in level_ir.layout.outputs}
    for k, phase in enumerate(path.phases):
        where = f"path {path_index} phase {k}"
        targets = {w.to_id for w in phase.wires}
        completed: Set[str] = set()
        i = 0
        while i < len(phase.wires):
            node_id = phase.wires[i].to_id
            j = i
            while j < len(phase.wires) and phase.wires[j].to_id == node_id:
                j += 1
            run = phase.wires[i:j]
            if node_id in completed:
                _fail(level_ir.name, "6 topological order",
                      f"{where}: {node_id}'s input wires appear in two separate runs; "
                      f"a multi-input node must be contiguous.")
            ports = [w.to_port for w in run]
            if ports != sorted(ports):
                _fail(level_ir.name, "6 topological order",
                      f"{where}: {node_id}'s input wires are not in ascending port order "
                      f"(got {ports}).")
            if len(set(ports)) != len(ports):
                _fail(level_ir.name, "6 topological order",
                      f"{where}: {node_id} has two wires on the same port {ports}.")
            for w in run:
                if w.from_id in targets and w.from_id not in completed:
                    _fail(level_ir.name, "6 topological order",
                          f"{where}: '{w}' appears before {w.from_id} has all of its own "
                          f"inputs, so the hint asks the player to wire a node that has "
                          f"no value yet.")
            completed.add(node_id)
            i = j

        if phase.is_final:
            seq = [w.to_id for w in phase.wires]
            first_out = next((n for n, t in enumerate(seq) if t in output_ids), None)
            if first_out is not None and any(t not in output_ids for t in seq[first_out:]):
                _fail(level_ir.name, "6 topological order",
                      f"{where}: a non-output wire follows an output-targeted wire; "
                      f"outputs are sinks and must all be last.")


def _check_referential_integrity(level_ir: LevelIR, path: Path, path_index: int) -> None:
    """Check 7. Every (type, slot) referenced exists in the emitted arrays.

    Binding resolution `push_error`s and silently drops the type otherwise,
    which degrades hints without failing loudly -- the reason this is checked
    here instead of being left to the game.
    """
    layout = level_ir.layout
    available: Set[Tuple[str, int]] = {e.ref for e in layout.all_entries}
    for k, phase in enumerate(path.phases):
        where = f"path {path_index} phase {k}"
        refs: List[Tuple[str, Tuple[str, int]]] = []
        for w in phase.wires:
            for node_id in (w.from_id, w.to_id):
                try:
                    refs.append((node_id, layout.ref(node_id)))
                except KeyError as exc:
                    _fail(level_ir.name, "7 referential integrity", f"{where}: {exc}")
        if phase.terminator is not None:
            try:
                ref = layout.ref(phase.terminator.store_id)
            except KeyError as exc:
                _fail(level_ir.name, "7 referential integrity", f"{where}: {exc}")
            if ref[0] != "STORE":
                _fail(level_ir.name, "7 referential integrity",
                      f"{where}: terminator names {phase.terminator.store_id!r}, which "
                      f"is a {ref[0]}, not a STORE.")
            refs.append((phase.terminator.store_id, ref))
        for node_id, ref in refs:
            if ref not in available:
                _fail(level_ir.name, "7 referential integrity",
                      f"{where}: {node_id!r} resolves to {ref}, which is not in the "
                      f"level's node arrays.")


def _check_engine_limits(level_ir: LevelIR, project: Project) -> None:
    """Check 8. Against LevelBuilder's INPUT_MAX / OPERATION_MAX / OUTPUT_MAX,
    parsed from level_builder.gd at run time rather than hardcoded. These have
    changed before -- OPERATION_MAX was 5 and is now 6."""
    limits = project.limits
    layout = level_ir.layout
    for label, entries, cap in (
        ("inputs", layout.inputs, limits.input_max),
        ("operations", layout.operations, limits.operation_max),
        ("outputs", layout.outputs, limits.output_max),
    ):
        if len(entries) > cap:
            _fail(level_ir.name, "8 engine limits",
                  f"{len(entries)} {label}, but LevelBuilder allows {cap}.")


def _check_display_ranges(level_ir: LevelIR, ranges: DisplayRanges) -> None:
    """Check 9. Every emitted value within its §9 range. Oversized numbers
    overflow the node's bounding box in game."""
    for entry in level_ir.layout.inputs + level_ir.layout.outputs:
        lo, hi = ranges.for_type(entry.node_type)
        if entry.value is None or not (lo <= entry.value <= hi):
            flag = "--input-range" if entry.node_type == "INPUT" else "--output-range"
            _fail(level_ir.name, "9 display range",
                  f"{entry.node_type} {entry.node_id} value {entry.value} is outside "
                  f"the {lo}..{hi} display range. If this level is meant to use a wider "
                  f"range, say so with {flag} so the widening is deliberate and recorded.")
    alo, ahi = ranges.add_value
    for entry in level_ir.layout.operations:
        if entry.node_type != "ADD_VALUE":
            continue
        if entry.value is None or not (alo <= entry.value <= ahi):
            _fail(level_ir.name, "9 display range",
                  f"ADD_VALUE {entry.node_id} offset {entry.value} is outside the "
                  f"{alo}..{ahi} display range. Widen deliberately with "
                  f"--add-value-range if that is intended.")


def validate_level(level, level_ir: LevelIR, project: Project,
                   ranges: DisplayRanges = DEFAULT_RANGES) -> None:
    """Run all nine checks. Raises `ValidationError` on the first failure."""
    store_slot_of = {
        e.node_id: e.slot for e in level_ir.layout.operations if e.node_type == "STORE"
    }

    _check_engine_limits(level_ir, project)          # 8
    _check_display_ranges(level_ir, ranges)          # 9

    if not level_ir.paths:
        _fail(level_ir.name, "structure", "no solution paths were produced.")

    for path_index, path in enumerate(level_ir.paths):
        if not path.phases:
            _fail(level_ir.name, "structure", f"path {path_index} has no phases.")
        if not path.phases[-1].is_final:
            _fail(level_ir.name, "structure",
                  f"path {path_index}'s last phase carries a terminator; the final "
                  f"phase must have none.")
        for k, phase in enumerate(path.phases[:-1]):
            if phase.is_final:
                _fail(level_ir.name, "structure",
                      f"path {path_index} phase {k} has no terminator but is not last.")

        _check_arithmetic(level, level_ir, path, path_index)            # 1
        _check_latch_placement(level_ir, path, path_index)              # 2
        _check_no_empty_phase(level_ir, path, path_index)               # 3
        _check_no_dead_latch(level_ir, path, path_index)                # 4
        _check_distinct_required_states(
            level_ir, path, path_index, store_slot_of)                  # 5
        _check_topological_order(level_ir, path, path_index)            # 6
        _check_referential_integrity(level_ir, path, path_index)        # 7
