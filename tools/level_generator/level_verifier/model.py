"""
Core data model for the node-puzzle level verifier.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, Optional, List
import json


VALID_TYPES = {"add", "sum", "subtract", "store"}


@dataclass(frozen=True)
class OpSpec:
    id: str
    type: str                # 'add' | 'sum' | 'subtract' | 'store'
    value: Optional[int] = None   # only for 'add'


@dataclass
class Level:
    name: str
    inputs: Dict[str, int]
    operations: Dict[str, OpSpec]
    outputs: Dict[str, int]
    warnings: List[str] = field(default_factory=list)

    def combinational_ops(self) -> Dict[str, OpSpec]:
        return {k: v for k, v in self.operations.items() if v.type in ("add", "sum", "subtract")}

    def store_ops(self) -> Dict[str, OpSpec]:
        return {k: v for k, v in self.operations.items() if v.type == "store"}

    def all_deletable_nodes(self) -> List[str]:
        """Inputs and operation nodes are candidates for the minimality leave-one-out pass.
        Output nodes are never deletable (they are the goal spec)."""
        return list(self.inputs.keys()) + list(self.operations.keys())

    def without_node(self, node_id: str) -> "Level":
        """Return a new Level with the given input or operation node removed."""
        if node_id in self.inputs:
            new_inputs = {k: v for k, v in self.inputs.items() if k != node_id}
            return Level(self.name, new_inputs, dict(self.operations), dict(self.outputs))
        elif node_id in self.operations:
            new_ops = {k: v for k, v in self.operations.items() if k != node_id}
            return Level(self.name, dict(self.inputs), new_ops, dict(self.outputs))
        else:
            raise KeyError(f"No such node: {node_id}")


def load_level(path: str) -> Level:
    with open(path, "r") as f:
        data = json.load(f)
    return level_from_dict(data)


def level_from_dict(data: dict) -> Level:
    name = data.get("name", "unnamed")
    inputs = dict(data.get("inputs", {}))
    outputs = dict(data.get("outputs", {}))
    raw_ops = data.get("operations", {})

    operations: Dict[str, OpSpec] = {}
    for op_id, spec in raw_ops.items():
        typ = spec.get("type")
        if typ not in VALID_TYPES:
            raise ValueError(f"Operation '{op_id}' has invalid type '{typ}'")
        val = spec.get("value") if typ == "add" else None
        if typ == "add" and val is None:
            raise ValueError(f"Add-value node '{op_id}' is missing 'value'")
        operations[op_id] = OpSpec(id=op_id, type=typ, value=val)

    # basic id collision check
    all_ids = list(inputs.keys()) + list(operations.keys()) + list(outputs.keys())
    dupes = {i for i in all_ids if all_ids.count(i) > 1}
    if dupes:
        raise ValueError(f"Duplicate node ids across inputs/operations/outputs: {sorted(dupes)}")

    warnings = validate(name, inputs, operations, outputs)
    return Level(name=name, inputs=inputs, operations=operations, outputs=outputs, warnings=warnings)


def validate(name, inputs, operations, outputs) -> List[str]:
    warnings = []

    if not (1 <= len(inputs) <= 4):
        warnings.append(f"Expected 1-4 inputs, found {len(inputs)}")
    if not (1 <= len(outputs) <= 4):
        warnings.append(f"Expected 1-4 outputs, found {len(outputs)}")
    if not (1 <= len(operations) <= 6):
        warnings.append(f"Expected 1-6 operations, found {len(operations)}")

    for iid, v in inputs.items():
        if not (-20 <= v <= 20):
            warnings.append(f"Input {iid}={v} is outside the -20..20 design range")
    for oid, v in outputs.items():
        if not (-20 <= v <= 20):
            warnings.append(f"Output {oid}={v} is outside the -20..20 design range")
    for opid, spec in operations.items():
        if spec.type == "add" and spec.value is not None and not (-20 <= spec.value <= 20):
            warnings.append(f"Add node {opid} value={spec.value} is outside the -20..20 design range")

    ivals = list(inputs.values())
    if len(set(ivals)) != len(ivals):
        warnings.append("Input values are not all distinct")

    ovals = list(outputs.values())
    if len(set(ovals)) != len(ovals):
        warnings.append("Output target values are not all distinct")

    return warnings
