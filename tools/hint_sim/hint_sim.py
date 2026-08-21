#!/usr/bin/env python3
"""
Faithful Python port of the runtime hint loop, for diagnosing which
SolutionPath the game actually walks.

Ports, line for line where it matters:
  SolutionPath.evaluate / _cursor_for_bindings / _score_bindings
  SolutionStep.is_satisfied / _required_connection_count
  LevelSolutionData.get_current_path / get_next_hint / get_next_hint_group
  GraphCanvas connect semantics + StoreNode.update_input auto-sever

Iteration order is preserved everywhere it can break a tie: live instances in
scene-child order, _permutations picking pool[0] first, _combine_candidates
nesting, and strict `>` comparisons so ties keep the incumbent.
"""
from __future__ import annotations

import itertools
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.normpath(os.path.join(_HERE, "..", "level_generator"))
sys.path[:0] = [os.path.join(GEN, "emitter"), os.path.join(GEN, "level_verifier"), GEN]

from project import load_project  # noqa: E402
import tres as tresmod  # noqa: E402

NULL = 9223372036854775807
ANY = -2147483648
COMMUTATIVE = {"SUM"}
FIXED_VALUE = {"INPUT", "OUTPUT", "ADD_VALUE"}


class Node:
    def __init__(self, node_type, slot, authored):
        self.type = node_type
        self.slot = slot
        self.authored = authored          # level-authored value
        self.store_value = NULL           # STORE only
        self.n_in = {"INPUT": 0, "OUTPUT": 1, "ADD_VALUE": 1,
                     "STORE": 1, "SUM": 2, "SUBTRACT": 2}[node_type]

    @property
    def key(self):
        return (self.type, self.slot)

    def get_value(self):
        """node.get("value") -- None for types with no `value` property."""
        if self.type == "STORE":
            return self.store_value
        if self.type in FIXED_VALUE:
            return self.authored
        return None

    def __repr__(self):
        return f"{self.type}{self.slot}"


class Graph:
    def __init__(self, nodes):
        self.nodes = nodes                 # scene-child order
        self.connections = []              # (from_node, from_port, to_node, to_port)

    def live(self, node_type):
        return [n for n in self.nodes if n.type == node_type]

    def output_value(self, node):
        if node.type == "INPUT":
            return node.authored
        if node.type == "STORE":
            return node.store_value
        args = []
        for p in range(node.n_in):
            src = next((c for c in self.connections if c[2] is node and c[3] == p), None)
            if src is None:
                return NULL
            v = self.output_value(src[0])
            if v == NULL:
                return NULL
            args.append(v)
        if node.type == "ADD_VALUE":
            return args[0] + node.authored
        if node.type == "SUM":
            return args[0] + args[1]
        if node.type == "SUBTRACT":
            return args[0] - args[1]
        if node.type == "OUTPUT":
            return args[0]
        return NULL

    def connect(self, fn, fp, tn, tp):
        """GraphCanvas.request_connection: an occupied input port severs first."""
        self.connections = [c for c in self.connections if not (c[2] is tn and c[3] == tp)]
        self.connections.append((fn, fp, tn, tp))
        if tn.type == "STORE":
            # StoreNode.update_input: latch, then _disconnect_input()
            v = self.output_value(fn)
            if v != NULL:
                tn.store_value = v
            self.connections = [c for c in self.connections
                                if not (c[2] is tn and c[3] == tp)]


class Step:
    def __init__(self, kind, d):
        self.kind = kind                   # "CONNECTION" | "STORE_VALUE"
        self.__dict__.update(d)

    def __repr__(self):
        if self.kind == "STORE_VALUE":
            return f"sv S{self.slot}={self.value}"
        return (f"{self.from_type}{self.from_slot}->{self.to_type}{self.to_slot}"
                f"p{self.to_port}")


def parse_level(path, project):
    name_of = {v: k for k, v in project.node_types.items()}
    subs, ext, resource = {}, {}, {}
    for kind, attrs, props in tresmod._parse_sections(open(path, encoding="utf-8").read()):
        if kind == "ext_resource":
            ext[attrs["id"]] = os.path.basename(attrs.get("path", ""))
        elif kind == "sub_resource":
            subs[attrs["id"]] = props
        elif kind == "resource":
            resource = props

    def cls(sid):
        return ext[re.search(r'ExtResource\("([^"]+)"\)', subs[sid]["script"]).group(1)]

    def ids(prop):
        return re.findall(r'SubResource\("([^"]+)"\)', resource.get(prop, ""))

    nodes, counter = [], {}
    for prop in ("inputs", "operations", "outputs"):
        for sid in ids(prop):
            p = subs[sid]
            t = name_of[int(p.get("type", "0"))]
            slot = counter.get(t, 0)
            counter[t] = slot + 1
            nodes.append(Node(t, slot, int(p.get("value", "0"))))

    sol = re.search(r'SubResource\("([^"]+)"\)', resource["level_solution_data"]).group(1)
    paths = []
    for pid in re.findall(r'SubResource\("([^"]+)"\)', subs[sol]["solution_paths"]):
        steps = []
        for sid in re.findall(r'SubResource\("([^"]+)"\)', subs[pid]["solution_steps"]):
            d = re.search(r'SubResource\("([^"]+)"\)', subs[sid]["step_data"]).group(1)
            p = subs[d]
            if cls(d) == "store_value_step_data.gd":
                steps.append(Step("STORE_VALUE", {"slot": int(p.get("slot", "0")),
                                                  "value": int(p.get("value", "0"))}))
            else:
                steps.append(Step("CONNECTION", {
                    "from_type": name_of[int(p.get("from_type", "0"))],
                    "from_slot": int(p.get("from_slot", "0")),
                    "from_port": int(p.get("from_port", "0")),
                    "from_value": int(p.get("from_value", ANY)),
                    "to_type": name_of[int(p.get("to_type", "0"))],
                    "to_slot": int(p.get("to_slot", "0")),
                    "to_port": int(p.get("to_port", "0")),
                    "to_value": int(p.get("to_value", ANY))}))
        paths.append(steps)
    return nodes, paths


class Path:
    def __init__(self, steps):
        self.steps = steps
        self.phase_conns, self.phase_terms = [], []
        cur = []
        for s in steps:
            if s.kind == "CONNECTION":
                cur.append(s)
            else:
                self.phase_conns.append(cur)
                self.phase_terms.append(s)
                cur = []
        self.phase_conns.append(cur)
        self.phase_terms.append(None)
        self._req = None

    def phase_count(self):
        return len(self.phase_conns)

    def required_states(self):
        if self._req is not None:
            return self._req
        slots = []
        for t in self.phase_terms:
            if t is not None and t.slot not in slots:
                slots.append(t.slot)
        out = []
        for k in range(self.phase_count()):
            st = {}
            for slot in slots:
                if not self._live_at(slot, k):
                    continue
                last = None
                for j in range(k):
                    t = self.phase_terms[j]
                    if t is not None and t.slot == slot:
                        last = t
                if last is not None:
                    st[slot] = last.value
            out.append(st)
        self._req = out
        return out

    def _live_at(self, slot, k):
        for j in range(k, self.phase_count()):
            if any(s.from_type == "STORE" and s.from_slot == slot
                   for s in self.phase_conns[j]):
                return True
            t = self.phase_terms[j]
            if t is not None and t.slot == slot:
                return False
        return False


def is_satisfied(step, bindings, graph, phase_steps):
    if step.kind == "STORE_VALUE":
        return False
    fn = bindings.get((step.from_type, step.from_slot))
    tn = bindings.get((step.to_type, step.to_slot))
    if fn is None or tn is None:
        return False
    if step.from_value != ANY and fn.get_value() != step.from_value:
        return False
    if step.to_value != ANY and tn.get_value() != step.to_value:
        return False

    if step.to_type in COMMUTATIVE:
        required = 0
        for other in phase_steps:
            if other.kind != "CONNECTION":
                continue
            if bindings.get((other.from_type, other.from_slot)) is not fn:
                continue
            if bindings.get((other.to_type, other.to_slot)) is not tn:
                continue
            if other.from_port != step.from_port:
                continue
            required += 1
            if other is step:
                break
        live = sum(1 for c in graph.connections
                   if c[0] is fn and c[1] == step.from_port and c[2] is tn)
        return live >= required

    return any(c[0] is fn and c[1] == step.from_port and c[2] is tn and c[3] == step.to_port
               for c in graph.connections)


def collect_slots(path):
    out = {}
    for s in path.steps:
        if s.kind == "STORE_VALUE":
            out.setdefault("STORE", [])
            if s.slot not in out["STORE"]:
                out["STORE"].append(s.slot)
        else:
            for t, sl in ((s.from_type, s.from_slot), (s.to_type, s.to_slot)):
                out.setdefault(t, [])
                if sl not in out[t]:
                    out[t].append(sl)
    return out


def slot_value_reqs(path, t):
    r = {}
    for s in path.steps:
        if s.kind != "CONNECTION":
            continue
        if s.from_type == t and s.from_value != ANY:
            r[s.from_slot] = s.from_value
        if s.to_type == t and s.to_value != ANY:
            r[s.to_slot] = s.to_value
    return r


def evaluate(path, graph):
    slots_by_type = collect_slots(path)
    cands = []
    for t, slots in slots_by_type.items():
        live = graph.live(t)
        if len(live) < len(slots):
            continue
        reqs = slot_value_reqs(path, t) if t in FIXED_VALUE else {}
        per = []
        for assign in itertools.permutations(live, len(slots)):
            if any(slots[i] in reqs and assign[i].get_value() != reqs[slots[i]]
                   for i in range(len(slots))):
                continue
            per.append({(t, slots[i]): assign[i] for i in range(len(slots))})
        cands.append(per)

    combined = [{}]
    for per in cands:
        combined = [{**a, **b} for a in combined for b in per]

    best = ({}, 0, (-1, -1, -1))
    for full in combined:
        cursor = 0
        for k in range(path.phase_count()):
            st = path.required_states()[k]
            if all(full.get(("STORE", sl)) is not None
                   and full[("STORE", sl)].get_value() == v for sl, v in st.items()):
                cursor = k
        sat = unsat = 0
        for k in range(cursor, path.phase_count()):
            ps = path.phase_conns[k]
            for s in ps:
                if is_satisfied(s, full, graph, ps):
                    if k == cursor:
                        sat += 1
                else:
                    unsat += 1
        score = (cursor, sat, -unsat)
        if score > best[2]:
            best = (full, cursor, score)
    return best


def get_current_path(paths, graph):
    best_score, chosen = (-1, -1, -1), None
    for i, p in enumerate(paths):
        b, cursor, score = evaluate(p, graph)
        if score > best_score:
            best_score, chosen = score, (i, p, b, cursor, score)
    return chosen


def next_hint_group(paths, graph):
    got = get_current_path(paths, graph)
    if got is None:
        return None
    i, p, bindings, cursor, score = got
    ps = p.phase_conns[cursor]
    first = next((s for s in ps if not is_satisfied(s, bindings, graph, ps)), None)
    if first is None:
        return (i, p, bindings, cursor, score, [])
    start = ps.index(first)
    run_to = bindings.get((first.to_type, first.to_slot))
    group = []
    for s in ps[start:]:
        if bindings.get((s.to_type, s.to_slot)) is not run_to:
            break
        if is_satisfied(s, bindings, graph, ps):
            continue
        group.append(s)
    return (i, p, bindings, cursor, score, group)


def run(tres_path, label, max_clicks=80):
    project = load_project()
    nodes, raw = parse_level(tres_path, project)
    paths = [Path(s) for s in raw]
    graph = Graph(nodes)

    print(f"\n{'='*76}\n{label}   ({len(paths)} paths)")
    for i, p in enumerate(paths):
        terms = [t for t in p.phase_terms if t]
        print(f"  path {i}: {' -> '.join(f'S{t.slot}={t.value}' for t in terms)}")
    print("-" * 76)

    prev = None
    for click in range(1, max_clicks + 1):
        got = next_hint_group(paths, graph)
        if got is None:
            print("  no path"); return
        i, p, bindings, cursor, score, group = got
        if not group:
            print(f"  click {click:>2}: path {i} cursor {cursor} score {score} -- COMPLETE")
            return
        if i != prev:
            print(f"  >>> now following path {i}")
            prev = i
        desc = ", ".join(str(s) for s in group)
        stores = [f"S{n.slot}={'?' if n.store_value == NULL else n.store_value}"
                  for n in graph.live("STORE")]
        print(f"  click {click:>2}: path {i} cursor {cursor} score {score:} "
              f"stores[{' '.join(stores)}] hint: {desc}")
        for s in group:
            fn = bindings[(s.from_type, s.from_slot)]
            tn = bindings[(s.to_type, s.to_slot)]
            graph.connect(fn, s.from_port, tn, s.to_port)
    print("  hit click limit")


if __name__ == "__main__":
    G = os.path.join(GEN, "emitter", "golden")
    run(os.path.join(G, "Store", "store_5.tres"), "store_5 (as emitted)")
    run(os.path.join(G, "Store", "store_4.tres"), "store_4 (as emitted)")
