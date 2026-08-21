"""
Read-at-run-time facts about the Godot project.

Everything here exists because a static copy of these values in a document
drifted and nobody noticed: LEVEL_GENERATION_AGENT_INSTRUCTIONS.md carried a
wrong script filename (`StoreValueStepData.gd`) and a stale `OPERATION_MAX` for
an unknown number of sessions. Nothing in the emitter hardcodes a UID, a
NodeType ordinal, or an engine limit -- they are all parsed out of the project
on every run, so a change on the Godot side shows up in emitted output with no
code edit here.

This module reads only:
  - HintSystem/node_type_registry.gd      (NodeType enum ordinals)
  - Levels/LevelBuilder/level_builder.gd  (INPUT_MAX / OPERATION_MAX / OUTPUT_MAX)
  - <script>.gd.uid                       (script UIDs)

It never writes to the project.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Dict, List, Tuple

_HERE = os.path.dirname(os.path.abspath(__file__))

# tools/level_generator/emitter -> repo root -> math-machine
DEFAULT_PROJECT_ROOT = os.path.normpath(
    os.path.join(_HERE, "..", "..", "..", "math-machine")
)


class ProjectReadError(RuntimeError):
    """The project could not be read, or does not look like what we expect.

    Always fatal. The emitter has no sensible fallback for "I could not find
    out what SUM's ordinal is" -- guessing is precisely the failure mode this
    module exists to prevent.
    """


# --------------------------------------------------------------------------
# Script table
# --------------------------------------------------------------------------
#
# Class name -> path relative to the Godot project root. The `.uid` sitting
# next to each of these is the authority for its UID; this table only says
# where to look.
#
# Filenames in the project are snake_case throughout. If one of these ever
# 404s, that is the bug -- do not "fix" it by guessing a different case.

SCRIPT_PATHS: Dict[str, str] = {
    "LevelData": "Levels/LevelData/level_data.gd",
    "GraphNodeData": "Levels/LevelData/graph_node_data.gd",
    "LevelSolutionData": "HintSystem/level_solution_data.gd",
    "SolutionPath": "HintSystem/solution_path.gd",
    "SolutionStep": "HintSystem/solution_step.gd",
    "StoreValueStepData": "HintSystem/store_value_step_data.gd",
    "ConnectionStepData": "HintSystem/connection_step_data.gd",
}

# Short, readable ext_resource ids, per §19.11 ("use readable ones ... you are
# writing these by hand and will need to check them").
SCRIPT_EXT_IDS: Dict[str, str] = {
    "GraphNodeData": "GND",
    "LevelData": "LD",
    "LevelSolutionData": "LSD",
    "SolutionPath": "SP",
    "SolutionStep": "SS",
    "StoreValueStepData": "SVD",
    "ConnectionStepData": "CSD",
}

_REGISTRY_REL = "HintSystem/node_type_registry.gd"
_BUILDER_REL = "Levels/LevelBuilder/level_builder.gd"


@dataclass(frozen=True)
class ScriptRef:
    class_name: str
    ext_id: str
    res_path: str   # "res://..."
    uid: str        # "uid://..."


@dataclass(frozen=True)
class EngineLimits:
    input_max: int
    operation_max: int
    output_max: int


@dataclass(frozen=True)
class Project:
    """Everything the emitter needs to know about the game project."""
    root: str
    node_types: Dict[str, int]          # "SUM" -> 3
    commutative: Tuple[str, ...]        # ("SUM",)
    fixed_value: Tuple[str, ...]        # ("INPUT", "OUTPUT", "ADD_VALUE")
    limits: EngineLimits
    scripts: Dict[str, ScriptRef]

    def ordinal(self, type_name: str) -> int:
        try:
            return self.node_types[type_name]
        except KeyError:
            raise ProjectReadError(
                f"NodeType {type_name!r} is not declared in {_REGISTRY_REL}. "
                f"Known types: {sorted(self.node_types)}"
            ) from None

    def script(self, class_name: str) -> ScriptRef:
        try:
            return self.scripts[class_name]
        except KeyError:
            raise ProjectReadError(f"No script registered for {class_name!r}") from None


def _read(root: str, rel: str) -> str:
    path = os.path.join(root, rel)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        raise ProjectReadError(
            f"Expected to find {rel} under the Godot project root ({root}) and did not. "
            f"Either --project-root is wrong or the project has been reorganised."
        ) from None


def _parse_node_types(source: str) -> Dict[str, int]:
    """Parse `enum NodeType { ... }` into name -> ordinal.

    Only bare members are accepted. GDScript permits explicit assignment
    (`INPUT = 7`); the registry does not use it today, and silently
    misinterpreting one as a bare member would repoint every emitted type
    field. So: refuse, loudly.
    """
    m = re.search(r"\benum\s+NodeType\s*\{(.*?)\}", source, re.DOTALL)
    if not m:
        raise ProjectReadError(
            f"Could not find `enum NodeType {{ ... }}` in {_REGISTRY_REL}."
        )
    body = m.group(1)
    body = re.sub(r"#.*", "", body)  # strip comments

    types: Dict[str, int] = {}
    for idx, raw in enumerate(p.strip() for p in body.split(",")):
        if not raw:
            continue
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", raw):
            raise ProjectReadError(
                f"Unexpected entry {raw!r} in the NodeType enum. This parser only "
                f"handles bare, implicitly-numbered members; explicit assignment "
                f"would change the ordinals and must not be guessed at."
            )
        types[raw] = idx
    if not types:
        raise ProjectReadError(f"NodeType enum in {_REGISTRY_REL} parsed as empty.")
    return types


def _parse_type_list(source: str, const_name: str) -> Tuple[str, ...]:
    """Parse `const <name>: Array[NodeType] = [ NodeType.A, NodeType.B, ]`."""
    m = re.search(
        r"\bconst\s+" + re.escape(const_name) + r"\s*:\s*Array\[NodeType\]\s*=\s*\[(.*?)\]",
        source,
        re.DOTALL,
    )
    if not m:
        raise ProjectReadError(
            f"Could not find `const {const_name}: Array[NodeType]` in {_REGISTRY_REL}."
        )
    body = re.sub(r"#.*", "", m.group(1))
    return tuple(re.findall(r"NodeType\.([A-Z][A-Z0-9_]*)", body))


def _parse_limits(source: str) -> EngineLimits:
    def const_int(name: str) -> int:
        m = re.search(r"\bconst\s+" + re.escape(name) + r"\s*:\s*int\s*=\s*(-?\d+)", source)
        if not m:
            raise ProjectReadError(
                f"Could not find `const {name}: int = ...` in {_BUILDER_REL}. "
                f"These limits are read rather than hardcoded precisely because "
                f"they change; a rename needs handling here, not a hardcoded value."
            )
        return int(m.group(1))

    return EngineLimits(
        input_max=const_int("INPUT_MAX"),
        operation_max=const_int("OPERATION_MAX"),
        output_max=const_int("OUTPUT_MAX"),
    )


def _read_uid(root: str, rel: str) -> str:
    uid_rel = rel + ".uid"
    text = _read(root, uid_rel).strip()
    if not text.startswith("uid://"):
        raise ProjectReadError(
            f"{uid_rel} does not contain a uid:// reference (got {text!r})."
        )
    return text


def load_project(root: str = DEFAULT_PROJECT_ROOT) -> Project:
    """Read every project-derived fact the emitter depends on. Fails loudly."""
    root = os.path.abspath(root)
    if not os.path.isdir(root):
        raise ProjectReadError(f"Project root is not a directory: {root}")

    registry_src = _read(root, _REGISTRY_REL)
    node_types = _parse_node_types(registry_src)
    commutative = _parse_type_list(registry_src, "commutative_types")
    fixed_value = _parse_type_list(registry_src, "fixed_value_types")

    for name in commutative + fixed_value:
        if name not in node_types:
            raise ProjectReadError(
                f"{_REGISTRY_REL} references NodeType.{name} but the enum does not declare it."
            )

    limits = _parse_limits(_read(root, _BUILDER_REL))

    scripts: Dict[str, ScriptRef] = {}
    for class_name, rel in SCRIPT_PATHS.items():
        _read(root, rel)  # existence check: a missing script is the StoreValueStepData.gd bug
        scripts[class_name] = ScriptRef(
            class_name=class_name,
            ext_id=SCRIPT_EXT_IDS[class_name],
            res_path="res://" + rel,
            uid=_read_uid(root, rel),
        )

    return Project(
        root=root,
        node_types=node_types,
        commutative=commutative,
        fixed_value=fixed_value,
        limits=limits,
        scripts=scripts,
    )


# Generator's type vocabulary -> Godot NodeType name (§19.3). The ordinal for
# each comes from the project, never from here.
GENERATOR_TYPE_TO_NODE_TYPE: Dict[str, str] = {
    "input": "INPUT",
    "output": "OUTPUT",
    "add": "ADD_VALUE",
    "sum": "SUM",
    "subtract": "SUBTRACT",
    "store": "STORE",
}


def node_type_for(generator_type: str) -> str:
    try:
        return GENERATOR_TYPE_TO_NODE_TYPE[generator_type]
    except KeyError:
        raise ProjectReadError(
            f"Generator emitted operation type {generator_type!r}, which has no "
            f"NodeType mapping. The type mapping has drifted -- stop rather than guess."
        ) from None


def script_ext_lines(project: Project, class_names: List[str]) -> List[str]:
    """`[ext_resource ...]` lines for the given classes, sorted by ext id so the
    header is stable across runs regardless of discovery order."""
    refs = [project.script(c) for c in class_names]
    refs.sort(key=lambda r: r.ext_id)
    return [
        f'[ext_resource type="Script" uid="{r.uid}" path="{r.res_path}" id="{r.ext_id}"]'
        for r in refs
    ]
