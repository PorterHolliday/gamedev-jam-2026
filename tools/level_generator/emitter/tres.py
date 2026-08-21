"""
CR-P4 -- `.tres` serialisation, and the re-parser used to round-trip it.

Godot resource text per §19.11 and §19.2. Nothing here hardcodes a UID or a
NodeType ordinal; both are read from the project on every run (see project.py),
which is what makes "changing a script's UID changes the emitted output on the
next run with no code edit" true rather than aspirational.

DEFAULT OMISSION
----------------
Every exported property still at its default is omitted. That is how Godot
itself saves, and it keeps diffs readable -- but it also means the default
values below are load-bearing. They are taken from the GDScript declarations:

    GraphNodeData        type = 0 (INPUT), value = 0
    ConnectionStepData   from_type = 0, from_slot = 0, from_port = 0,
                         from_value = ANY_VALUE, to_type = 0, to_slot = 0,
                         to_port = 0, to_value = ANY_VALUE
    StoreValueStepData   value = 0, slot = 0

ANY_VALUE (-2147483648) means "don't care" and is never written literally --
the line is omitted instead (§19.7).

UIDs ON EMITTED FILES
---------------------
§19.11 says to omit `uid=` from the header so Godot assigns one on first
import. That is right for a new file and wrong for regenerating an existing
one: `level_manager.tscn` references levels by uid *and* path, and dropping a
uid churns that file. So: an existing target's header uid is preserved
verbatim; a new file gets no uid line and Godot assigns one.
"""
from __future__ import annotations

import os
import re
from typing import Dict, List, Optional, Sequence, Tuple

from ir import Layout, LevelIR, Path, Phase
from project import Project

ANY_VALUE = -2147483648

_HEADER_UID_RE = re.compile(r'^\[gd_resource\b[^\]]*\buid="(uid://[^"]+)"')


# --------------------------------------------------------------------------
# Canonical projection -- the form both the emitter and the parser agree on
# --------------------------------------------------------------------------

Endpoint = Tuple[str, int, int]              # (NodeType name, slot, port)
WireRef = Tuple[Endpoint, Endpoint]
TermRef = Optional[Tuple[int, int]]          # (store slot, value)
PhaseRef = Tuple[Tuple[WireRef, ...], TermRef]
PathRef = Tuple[PhaseRef, ...]


def project_path(path: Path, layout: Layout) -> PathRef:
    """Reduce a `Path` to `(type, slot, port)` space -- exactly what Godot
    reads, with generator ids erased.

    Round-tripping in this space rather than in generator ids is deliberate: it
    compares what the game will actually see, and it is the only space the
    re-parser can reach, since a `.tres` has no memory of `P1` or `S2`.
    """
    def endpoint(node_id: str, port: int) -> Endpoint:
        node_type, slot = layout.ref(node_id)
        return (node_type, slot, port)

    out: List[PhaseRef] = []
    for phase in path.phases:
        wires = tuple(
            (endpoint(w.from_id, w.from_port), endpoint(w.to_id, w.to_port))
            for w in phase.wires
        )
        term: TermRef = None
        if phase.terminator is not None:
            _, slot = layout.ref(phase.terminator.store_id)
            term = (slot, phase.terminator.value)
        out.append((wires, term))
    return tuple(out)


def project_level(level_ir: LevelIR) -> Tuple[PathRef, ...]:
    return tuple(project_path(p, level_ir.layout) for p in level_ir.paths)


# --------------------------------------------------------------------------
# Serialisation
# --------------------------------------------------------------------------

def _block(header: str, lines: Sequence[str]) -> str:
    return "\n".join([header, *lines]) + "\n"


def _graph_node_block(sub_id: str, entry, project: Project) -> str:
    gnd = project.script("GraphNodeData")
    lines = [f'script = ExtResource("{gnd.ext_id}")']
    ordinal = project.ordinal(entry.node_type)
    if ordinal != 0:                                  # default is INPUT (0)
        lines.append(f"type = {ordinal}")
    if entry.value is not None and entry.value != 0:  # default is 0
        lines.append(f"value = {entry.value}")
    lines.append(f'metadata/_custom_type_script = "{gnd.uid}"')
    return _block(f'[sub_resource type="Resource" id="{sub_id}"]', lines)


def _connection_block(sub_id: str, wire, layout: Layout, project: Project) -> str:
    csd = project.script("ConnectionStepData")
    from_type, from_slot = layout.ref(wire.from_id)
    to_type, to_slot = layout.ref(wire.to_id)
    from_entry = layout.entry(wire.from_id)
    to_entry = layout.entry(wire.to_id)

    lines = [f'script = ExtResource("{csd.ext_id}")']
    # Declaration order in connection_step_data.gd. Every omitted line is a
    # property sitting at its default.
    if project.ordinal(from_type) != 0:
        lines.append(f"from_type = {project.ordinal(from_type)}")
    if from_slot != 0:
        lines.append(f"from_slot = {from_slot}")
    if wire.from_port != 0:
        lines.append(f"from_port = {wire.from_port}")
    if from_type in project.fixed_value:
        lines.append(f"from_value = {_fixed_value(from_entry)}")
    if project.ordinal(to_type) != 0:
        lines.append(f"to_type = {project.ordinal(to_type)}")
    if to_slot != 0:
        lines.append(f"to_slot = {to_slot}")
    if wire.to_port != 0:
        lines.append(f"to_port = {wire.to_port}")
    if to_type in project.fixed_value:
        lines.append(f"to_value = {_fixed_value(to_entry)}")
    lines.append(f'metadata/_custom_type_script = "{csd.uid}"')
    return _block(f'[sub_resource type="Resource" id="{sub_id}"]', lines)


def _fixed_value(entry) -> int:
    """The level-authored value for a fixed-value type.

    For ADD_VALUE this is the node's *offset*, never the value flowing through
    it. `SolutionStep._matches_value` compares against `node.value`, which for
    an Add Value node is the offset -- and the verifier's transcript prints the
    flowing value, which is the trap §19.7 exists to name. Layout already
    stores the offset, so the trap cannot be reached from here; this assertion
    exists to keep it that way.
    """
    if entry.value is None:
        raise ValueError(
            f"{entry.node_type} {entry.node_id} is a fixed-value type but carries no "
            f"value. This is a layout bug, not a level bug."
        )
    return entry.value


def _store_value_block(sub_id: str, slot: int, value: int, project: Project) -> str:
    svd = project.script("StoreValueStepData")
    lines = [f'script = ExtResource("{svd.ext_id}")']
    if value != 0:
        lines.append(f"value = {value}")
    if slot != 0:
        lines.append(f"slot = {slot}")
    lines.append(f'metadata/_custom_type_script = "{svd.uid}"')
    return _block(f'[sub_resource type="Resource" id="{sub_id}"]', lines)


def _step_block(sub_id: str, data_id: str, project: Project) -> str:
    ss = project.script("SolutionStep")
    return _block(
        f'[sub_resource type="Resource" id="{sub_id}"]',
        [
            f'script = ExtResource("{ss.ext_id}")',
            f'step_data = SubResource("{data_id}")',
            f'metadata/_custom_type_script = "{ss.uid}"',
        ],
    )


def _typed_array(ext_id: str, sub_ids: Sequence[str]) -> str:
    inner = ", ".join(f'SubResource("{s}")' for s in sub_ids)
    return f'Array[ExtResource("{ext_id}")]([{inner}])'


def existing_header_uid(path: str) -> Optional[str]:
    """The `uid=` on an existing file's `[gd_resource]` header, or None."""
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        first = fh.readline()
    m = _HEADER_UID_RE.match(first.strip())
    return m.group(1) if m else None


def render(level_ir: LevelIR, project: Project, uid: Optional[str] = None) -> str:
    """Serialise to Godot resource text.

    Block order per §19.11: sub-resources always precede anything referencing
    them -- nodes, then step data and steps, then paths, then the solution,
    then `[resource]`. No comment lines are emitted; Godot tolerates them but
    the editor drops them on first save, producing a spurious diff.
    """
    layout = level_ir.layout
    parts: List[str] = []

    header = '[gd_resource type="Resource" script_class="LevelData" format=3'
    if uid:
        header += f' uid="{uid}"'
    header += "]"
    parts.append(header + "\n")

    has_terminator = any(
        phase.terminator is not None for p in level_ir.paths for phase in p.phases
    )
    used = ["GraphNodeData", "LevelData", "LevelSolutionData", "SolutionPath",
            "SolutionStep", "ConnectionStepData"]
    if has_terminator:
        used.append("StoreValueStepData")

    refs = sorted((project.script(c) for c in used), key=lambda r: r.ext_id)
    parts.append(
        "\n".join(
            f'[ext_resource type="Script" uid="{r.uid}" path="{r.res_path}" id="{r.ext_id}"]'
            for r in refs
        )
        + "\n"
    )

    input_ids, op_ids, output_ids = [], [], []
    for prefix, entries, collector in (
        ("In", layout.inputs, input_ids),
        ("Op", layout.operations, op_ids),
        ("Out", layout.outputs, output_ids),
    ):
        for i, entry in enumerate(entries):
            sub_id = f"{prefix}{i}"
            collector.append(sub_id)
            parts.append(_graph_node_block(sub_id, entry, project))

    path_ids: List[str] = []
    for path_index, path in enumerate(level_ir.paths):
        step_ids: List[str] = []
        conn_n = 0
        term_n = 0
        for phase in path.phases:
            for wire in phase.wires:
                data_id = f"D_p{path_index}_c{conn_n}"
                step_id = f"S_p{path_index}_c{conn_n}"
                conn_n += 1
                parts.append(_connection_block(data_id, wire, layout, project))
                parts.append(_step_block(step_id, data_id, project))
                step_ids.append(step_id)
            if phase.terminator is not None:
                _, slot = layout.ref(phase.terminator.store_id)
                data_id = f"D_p{path_index}_sv{term_n}"
                step_id = f"S_p{path_index}_sv{term_n}"
                term_n += 1
                parts.append(
                    _store_value_block(data_id, slot, phase.terminator.value, project)
                )
                parts.append(_step_block(step_id, data_id, project))
                step_ids.append(step_id)

        sp = project.script("SolutionPath")
        ss = project.script("SolutionStep")
        sub_id = f"Path{path_index}"
        path_ids.append(sub_id)
        parts.append(
            _block(
                f'[sub_resource type="Resource" id="{sub_id}"]',
                [
                    f'script = ExtResource("{sp.ext_id}")',
                    f"solution_steps = {_typed_array(ss.ext_id, step_ids)}",
                    f'metadata/_custom_type_script = "{sp.uid}"',
                ],
            )
        )

    lsd = project.script("LevelSolutionData")
    sp = project.script("SolutionPath")
    parts.append(
        _block(
            '[sub_resource type="Resource" id="Solution"]',
            [
                f'script = ExtResource("{lsd.ext_id}")',
                f"solution_paths = {_typed_array(sp.ext_id, path_ids)}",
                f'metadata/_custom_type_script = "{lsd.uid}"',
            ],
        )
    )

    ld = project.script("LevelData")
    gnd = project.script("GraphNodeData")
    parts.append(
        _block(
            "[resource]",
            [
                f'script = ExtResource("{ld.ext_id}")',
                f"inputs = {_typed_array(gnd.ext_id, input_ids)}",
                f"operations = {_typed_array(gnd.ext_id, op_ids)}",
                f"outputs = {_typed_array(gnd.ext_id, output_ids)}",
                'level_solution_data = SubResource("Solution")',
                f'metadata/_custom_type_script = "{ld.uid}"',
            ],
        )
    )

    return "\n".join(parts)


# --------------------------------------------------------------------------
# Re-parsing (round-trip)
# --------------------------------------------------------------------------

class TresParseError(RuntimeError):
    pass


_SECTION_RE = re.compile(r"^\[(\w+)([^\]]*)\]\s*$")
_ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
_PROP_RE = re.compile(r"^(\S+)\s*=\s*(.*)$")
_SUBREF_RE = re.compile(r'SubResource\("([^"]+)"\)')
_EXTREF_RE = re.compile(r'ExtResource\("([^"]+)"\)')


def _parse_sections(text: str):
    """Yield (kind, attrs, props) for each top-level block."""
    kind: Optional[str] = None
    attrs: Dict[str, str] = {}
    props: Dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = _SECTION_RE.match(line)
        if m:
            if kind is not None:
                yield kind, attrs, props
            kind = m.group(1)
            attrs = dict(_ATTR_RE.findall(m.group(2)))
            props = {}
            continue
        if kind is None:
            continue
        pm = _PROP_RE.match(line)
        if pm:
            props[pm.group(1)] = pm.group(2).strip()
    if kind is not None:
        yield kind, attrs, props


def parse(text: str, project: Project) -> Tuple[Tuple[PathRef, ...], Dict[str, List[Tuple[str, int, int]]]]:
    """Re-parse emitted resource text back into canonical `(type, slot, port)`
    space, plus the three node arrays.

    Rebuilds the `(type, slot)` map from the file's OWN arrays rather than
    trusting the one that produced it -- which is the point of the round-trip:
    it catches slot numbers that no longer match post-ordering array positions.
    """
    name_of_ordinal = {v: k for k, v in project.node_types.items()}
    ext_by_id: Dict[str, str] = {}
    subs: Dict[str, Tuple[str, Dict[str, str]]] = {}
    resource_props: Dict[str, str] = {}

    for kind, attrs, props in _parse_sections(text):
        if kind == "ext_resource":
            ext_by_id[attrs["id"]] = attrs.get("path", "")
        elif kind == "sub_resource":
            script_id = _EXTREF_RE.search(props.get("script", ""))
            if script_id is None:
                raise TresParseError(f"sub_resource {attrs.get('id')} has no script.")
            subs[attrs["id"]] = (ext_by_id.get(script_id.group(1), ""), props)
        elif kind == "resource":
            resource_props = props

    def class_of(sub_id: str) -> str:
        path = subs[sub_id][0]
        return os.path.basename(path)

    def array_ids(prop: str) -> List[str]:
        return _SUBREF_RE.findall(resource_props.get(prop, ""))

    # Slot is the 0-based index among nodes of the same NodeType across the
    # whole file, so the counter is shared by all three arrays -- inputs are
    # all INPUT and outputs all OUTPUT, so in practice only `operations` mixes.
    arrays: Dict[str, List[Tuple[str, int, int]]] = {}
    slot_counter: Dict[str, int] = {}
    for prop in ("inputs", "operations", "outputs"):
        entries: List[Tuple[str, int, int]] = []
        for sub_id in array_ids(prop):
            props = subs[sub_id][1]
            ordinal = int(props.get("type", "0"))
            node_type = name_of_ordinal.get(ordinal)
            if node_type is None:
                raise TresParseError(f"Unknown NodeType ordinal {ordinal} in {sub_id}.")
            slot = slot_counter.get(node_type, 0)
            slot_counter[node_type] = slot + 1
            entries.append((node_type, slot, int(props.get("value", "0"))))
        arrays[prop] = entries

    solution_id = _SUBREF_RE.search(resource_props.get("level_solution_data", ""))
    if solution_id is None:
        raise TresParseError("[resource] has no level_solution_data.")
    path_ids = _SUBREF_RE.findall(subs[solution_id.group(1)][1].get("solution_paths", ""))

    paths: List[PathRef] = []
    for path_sub in path_ids:
        step_ids = _SUBREF_RE.findall(subs[path_sub][1].get("solution_steps", ""))
        phases: List[PhaseRef] = []
        wires: List[WireRef] = []
        for step_sub in step_ids:
            data_ref = _SUBREF_RE.search(subs[step_sub][1].get("step_data", ""))
            if data_ref is None:
                raise TresParseError(f"SolutionStep {step_sub} has no step_data.")
            data_sub = data_ref.group(1)
            cls = class_of(data_sub)
            props = subs[data_sub][1]
            if cls == "connection_step_data.gd":
                wires.append((
                    (name_of_ordinal[int(props.get("from_type", "0"))],
                     int(props.get("from_slot", "0")),
                     int(props.get("from_port", "0"))),
                    (name_of_ordinal[int(props.get("to_type", "0"))],
                     int(props.get("to_slot", "0")),
                     int(props.get("to_port", "0"))),
                ))
            elif cls == "store_value_step_data.gd":
                phases.append((tuple(wires), (int(props.get("slot", "0")),
                                              int(props.get("value", "0")))))
                wires = []
            else:
                raise TresParseError(f"Unexpected step_data script {cls!r} in {data_sub}.")
        phases.append((tuple(wires), None))  # trailing run = final phase
        paths.append(tuple(phases))

    return tuple(paths), arrays


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
