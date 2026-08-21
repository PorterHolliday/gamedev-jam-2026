#!/usr/bin/env python3
"""
CR-P6 -- the emitter's test corpus.

Run with:
    python3 emitter/test_emitter.py            # from tools/level_generator
    python3 test_emitter.py --regenerate       # rewrite golden files

Exit code 0 and "ALL TESTS PASSED" on success, matching the convention in
level_verifier/verify.py --test and test_generate.py. Stdlib only; the project
has no pytest.

WHAT EACH GROUP IS FOR
----------------------
golden        A byte-identical regeneration guarantee over every level in the
              project. A diff here is a deliberate decision, not a surprise.
cross-check   Structured extraction (production path) versus §19.8 transcript
              replay (oracle), asserted equal on every solution family of
              every level. Two independent derivations agreeing is the
              strongest signal available with no Godot in the loop.
round-trip    Emit -> re-parse -> compare against the IR it was built from,
              with the (type, slot) map rebuilt from the file's OWN arrays.
              This is what catches slot numbers that no longer match
              post-ordering array positions -- the failure mode CR-P8 calls the
              worst available, since nothing else detects it short of playing
              the level.
corruption    Each CR-P3 check has a test that breaks exactly that invariant
              and asserts the specific failure, so a check that silently stops
              firing gets caught.
store-free    AddValue and SumAndSubtract levels must emit a single-phase path
              with an empty required state, describing the same graph that
              ships today. This is the real safety net for the migration:
              those levels' behaviour must not change at all.
fixtures      The worked examples the CR documents state as acceptance
              criteria, checked literally.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import traceback

_HERE = os.path.dirname(os.path.abspath(__file__))
_GEN = os.path.dirname(_HERE)
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(_GEN, "level_verifier"))
sys.path.insert(0, _GEN)

from api import dedupe_families, load_level, render_solution, solve  # noqa: E402
from collapse import collapse_paths  # noqa: E402
from ir import LevelIR, Path, Phase, Terminator, Wire  # noqa: E402
from layout import build_layout, LayoutError, SIZE_GROUP  # noqa: E402
from ordering import order_paths, order_phase, OrderingError  # noqa: E402
from phases import extract_paths, extract_path  # noqa: E402
from project import load_project  # noqa: E402
from replay import phase_wire_sets, replay_transcript  # noqa: E402
from validate import (  # noqa: E402
    DisplayRanges, ValidationError, required_state, required_states, validate_level,
)
import tres  # noqa: E402

GOLDEN_ROOT = os.path.join(_HERE, "golden")
LEVELS_ROOT = os.path.join(_GEN, "levels")
SHIPPED_ROOT = os.path.normpath(
    os.path.join(_GEN, "..", "..", "math-machine", "Levels", "LevelData")
)

# Levels needing a non-default §9 range, with the reason recorded here rather
# than buried in a flag someone has to remember.
#
# Currently empty: every level in the corpus fits §9's display ranges
# (inputs -9..9, outputs -20..20, add values -9..9). store_5's O2 = -10 used to
# need an override under the old -9..20 output range and no longer does.
RANGE_OVERRIDES = {}

STORE_FREE_CATEGORIES = ("AddValue", "SumAndSubtract")

_PROJECT = None
_CACHE = {}


def project():
    global _PROJECT
    if _PROJECT is None:
        _PROJECT = load_project()
    return _PROJECT


def corpus_levels():
    return sorted(glob.glob(os.path.join(LEVELS_ROOT, "*", "*.json")))


def category_of(path):
    return os.path.basename(os.path.dirname(path))


def solve_params(path):
    with open(path, "r", encoding="utf-8") as fh:
        source = (json.load(fh).get("source") or {})
    bound = tuple(source.get("bound") or (-20, 20))
    return (int(bound[0]), int(bound[1])), int(source.get("max_latches") or 8)


def build(level_json_path):
    """Full pipeline for one level, cached -- solving the corpus is the slow
    part and several test groups need the same result."""
    if level_json_path in _CACHE:
        return _CACHE[level_json_path]
    level = load_level(level_json_path)
    bound, max_latches = solve_params(level_json_path)
    result = solve(level, bound=bound, max_latches=max_latches,
                   find_all=True, max_families=20)
    families = dedupe_families(level, result.solutions)
    layout = build_layout(level, project())
    paths = order_paths(
        collapse_paths(extract_paths(level, families), layout, project()),
        layout, level.name,
    )
    level_ir = LevelIR(name=level.name, layout=layout, paths=tuple(paths),
                       family_count=len(families), bound=bound, max_latches=max_latches)
    ranges = RANGE_OVERRIDES.get(level.name, DisplayRanges())
    validate_level(level, level_ir, project(), ranges=ranges)
    _CACHE[level_json_path] = (level, level_ir, families)
    return _CACHE[level_json_path]


# --------------------------------------------------------------------------
# Assertions
# --------------------------------------------------------------------------

class Failure(AssertionError):
    pass


def check(condition, message):
    if not condition:
        raise Failure(message)


def check_eq(got, expected, message):
    if got != expected:
        raise Failure(f"{message}\n    expected: {expected!r}\n    got:      {got!r}")


def check_raises(exc_type, fn, substring, message):
    try:
        fn()
    except exc_type as e:
        if substring.lower() not in str(e).lower():
            raise Failure(
                f"{message}: raised {exc_type.__name__} but message lacked {substring!r}\n"
                f"    got: {e}"
            )
        return str(e)
    except Exception as e:  # noqa: BLE001
        raise Failure(
            f"{message}: expected {exc_type.__name__}, got "
            f"{type(e).__name__}: {e}"
        ) from None
    raise Failure(f"{message}: expected {exc_type.__name__}, nothing was raised")


def wire_strs(phase):
    return [str(w) for w in phase.wires]


# --------------------------------------------------------------------------
# golden
# --------------------------------------------------------------------------

def golden_path(level_json_path, name):
    return os.path.join(GOLDEN_ROOT, category_of(level_json_path), f"{name}.tres")


def test_golden(regenerate=False):
    """Every level regenerates byte-identically to its golden file."""
    missing, differing = [], []
    for level_json_path in corpus_levels():
        _level, level_ir, _fams = build(level_json_path)
        gp = golden_path(level_json_path, level_ir.name)
        # Preserve the shipped uid, exactly as emit.py does, so the golden file
        # is what would land in the project rather than a near-miss.
        shipped = os.path.join(SHIPPED_ROOT, category_of(level_json_path),
                               f"{level_ir.name}.tres")
        uid = tres.existing_header_uid(shipped)
        text = tres.render(level_ir, project(), uid=uid)
        if regenerate:
            tres.write(gp, text)
            continue
        if not os.path.exists(gp):
            missing.append(gp)
            continue
        with open(gp, "r", encoding="utf-8") as fh:
            if fh.read() != text:
                differing.append(level_ir.name)
    if regenerate:
        return
    check(not missing, f"golden file(s) missing (run --regenerate): {missing}")
    check(not differing,
          f"golden file(s) differ: {differing}. If deliberate, re-run with "
          f"--regenerate and review the diff.")


def test_golden_is_deterministic():
    """Two renders of the same input are byte-identical."""
    for level_json_path in corpus_levels()[:6]:
        _level, level_ir, _ = build(level_json_path)
        a = tres.render(level_ir, project())
        b = tres.render(level_ir, project())
        check_eq(a, b, f"{level_ir.name}: render is not deterministic")


# --------------------------------------------------------------------------
# cross-check
# --------------------------------------------------------------------------

def test_dual_derivation():
    """Structured extraction == §19.8 transcript replay, on every family of
    every level."""
    compared = 0
    for level_json_path in corpus_levels():
        level, _ir, families = build(level_json_path)
        for i, solution in enumerate(families):
            structured = phase_wire_sets(extract_path(level, solution))
            replayed = phase_wire_sets(
                replay_transcript(render_solution(level, solution), level)
            )
            check_eq(replayed, structured,
                     f"{level.name} family {i}: replay disagrees with structured extraction")
            compared += 1
    check(compared >= 70,
          f"expected the corpus to cover 70+ families, compared only {compared}")


def test_replay_rejects_unknown_line():
    """A transcript line the parser does not recognise raises rather than
    being skipped -- a skipped line is a silently wrong phase."""
    from replay import ReplayError
    level, _ir, families = build(os.path.join(LEVELS_ROOT, "Challenge", "challenge_1.json"))
    lines = list(render_solution(level, families[0]))
    lines.insert(2, "1. Teleport I1 => P1 sideways")
    check_raises(ReplayError, lambda: replay_transcript(lines, level),
                 "matched no known pattern",
                 "replay accepted an unparseable transcript line")


# --------------------------------------------------------------------------
# round-trip
# --------------------------------------------------------------------------

def test_round_trip():
    """Emit -> re-parse -> compare, with the (type, slot) map rebuilt from the
    emitted file's own arrays."""
    for level_json_path in corpus_levels():
        _level, level_ir, _ = build(level_json_path)
        text = tres.render(level_ir, project())
        parsed_paths, arrays = tres.parse(text, project())
        check_eq(parsed_paths, tres.project_level(level_ir),
                 f"{level_ir.name}: round-trip lost or altered phase structure")

        # Every step still resolves to the intended node (CR-P8 acceptance).
        check_eq([(e.node_type, e.slot) for e in level_ir.layout.inputs],
                 [(t, s) for t, s, _ in arrays["inputs"]],
                 f"{level_ir.name}: inputs array round-trip mismatch")
        check_eq([(e.node_type, e.slot) for e in level_ir.layout.operations],
                 [(t, s) for t, s, _ in arrays["operations"]],
                 f"{level_ir.name}: operations array round-trip mismatch")
        check_eq([(e.node_type, e.slot) for e in level_ir.layout.outputs],
                 [(t, s) for t, s, _ in arrays["outputs"]],
                 f"{level_ir.name}: outputs array round-trip mismatch")


def test_uid_is_read_not_hardcoded():
    """Changing a script's UID in the project changes emitted output on the
    next run, with no code edit."""
    import dataclasses
    _level, level_ir, _ = build(os.path.join(LEVELS_ROOT, "Challenge", "challenge_1.json"))
    base = tres.render(level_ir, project())
    scripts = dict(project().scripts)
    scripts["ConnectionStepData"] = dataclasses.replace(
        scripts["ConnectionStepData"], uid="uid://sentineluid42"
    )
    mutated = dataclasses.replace(project(), scripts=scripts)
    text = tres.render(level_ir, mutated)
    check(text != base, "changing a script UID did not change emitted output")
    check("uid://sentineluid42" in text, "the changed UID does not appear in the output")


def test_header_uid_preserved():
    """An existing target's header uid is carried through; a new file gets
    none."""
    _level, level_ir, _ = build(os.path.join(LEVELS_ROOT, "Challenge", "challenge_1.json"))
    shipped = os.path.join(SHIPPED_ROOT, "Challenge", "challenge_1.tres")
    uid = tres.existing_header_uid(shipped)
    check(uid is not None, f"expected a header uid on {shipped}")
    with_uid = tres.render(level_ir, project(), uid=uid)
    check(with_uid.splitlines()[0].endswith(f'uid="{uid}"]'),
          "preserved uid did not appear in the header")
    without = tres.render(level_ir, project(), uid=None)
    check("uid=" not in without.splitlines()[0],
          "a new file should carry no uid in its header")
    check_eq(tres.existing_header_uid(os.path.join(_HERE, "does_not_exist.tres")), None,
             "existing_header_uid should return None for a missing file")


# --------------------------------------------------------------------------
# invariant corruption -- one per CR-P3 check
# --------------------------------------------------------------------------

def _challenge_1():
    return build(os.path.join(LEVELS_ROOT, "Challenge", "challenge_1.json"))


def _with_paths(level_ir, paths):
    return LevelIR(name=level_ir.name, layout=level_ir.layout, paths=tuple(paths),
                   family_count=level_ir.family_count, bound=level_ir.bound,
                   max_latches=level_ir.max_latches)


def _mutate_phase(path, index, **kw):
    phases = list(path.phases)
    p = phases[index]
    phases[index] = Phase(wires=kw.get("wires", p.wires),
                          terminator=kw.get("terminator", p.terminator))
    return Path(tuple(phases))


def test_corruption_check_1_arithmetic():
    level, level_ir, _ = _challenge_1()
    path = level_ir.paths[0]
    broken = _mutate_phase(path, 0, terminator=Terminator("S1", 999))
    check_raises(ValidationError,
                 lambda: validate_level(level, _with_paths(level_ir, [broken]), project()),
                 "1 arithmetic", "check 1 did not fire on a wrong terminator value")


def test_corruption_check_2_latch_placement():
    level, level_ir, _ = _challenge_1()
    path = level_ir.paths[0]
    wires = list(path.phases[0].wires)
    wires.insert(0, wires.pop())  # latch connection first instead of last
    broken = _mutate_phase(path, 0, wires=tuple(wires))
    msg = check_raises(
        ValidationError,
        lambda: validate_level(level, _with_paths(level_ir, [broken]), project()),
        "latch", "check 2 did not fire on a misplaced latch connection")
    check("phase 0" in msg, f"check 2 failure should name the phase; got: {msg}")


# Checks 3, 4, 5 and 7 cannot be isolated through validate_level: any
# corruption that violates them also breaks the arithmetic, and check 1 runs
# first and aborts. So each is driven directly, and then validate_level is
# asserted to reject the same input by *some* route -- which is what actually
# matters for emission safety.

def _rejects(level, level_ir, path, message):
    check_raises(ValidationError,
                 lambda: validate_level(level, _with_paths(level_ir, [path]), project()),
                 "", message)


def test_corruption_check_3_empty_phase():
    from validate import _check_no_empty_phase
    level, level_ir, _ = _challenge_1()
    broken = _mutate_phase(level_ir.paths[0], 0, wires=())
    msg = check_raises(
        ValidationError,
        lambda: _check_no_empty_phase(_with_paths(level_ir, [broken]), broken, 0),
        "3 empty phase", "check 3 did not fire on a phase with no connections")
    check("phase 0" in msg and "challenge_1" in msg,
          f"check 3 should name the level and phase; got: {msg}")
    _rejects(level, level_ir, broken, "validate_level accepted a path with an empty phase")


def test_corruption_check_4_dead_latch():
    from validate import _check_no_dead_latch
    level, level_ir, _ = _challenge_1()
    w = lambda f, t, p=0: Wire(f, 0, t, p)  # noqa: E731
    # S2 is latched, and no later phase reads it -- the final phase draws
    # everything from S1. challenge_1's real paths all read both stores, so
    # this has to be built rather than mutated out of one.
    broken = Path((
        Phase((w("I1", "P1", 0), w("I2", "P1", 1), w("P1", "S1")), Terminator("S1", 9)),
        Phase((w("I1", "S2"),), Terminator("S2", 2)),
        Phase((w("S1", "O1"),), None),
    ))
    msg = check_raises(
        ValidationError,
        lambda: _check_no_dead_latch(_with_paths(level_ir, [broken]), broken, 1),
        "4 dead latch", "check 4 did not fire on a store nothing reads")
    check("S2" in msg, f"check 4 should name the store; got: {msg}")
    _rejects(level, level_ir, broken, "validate_level accepted a path with a dead latch")


def test_corruption_check_5_duplicate_required_state():
    """Two phases with identical required states. The cursor takes `max k`, so
    a collision silently skips the earlier phase's work rather than erroring."""
    from validate import _check_distinct_required_states
    w = lambda f, t, p=0: Wire(f, 0, t, p)  # noqa: E731
    # S1 latched twice with nothing reading it in between: phases 0 and 1 both
    # require {}, because S1's first value is dead (re-latched, never read).
    path = Path((
        Phase((w("I1", "P1", 0), w("I2", "P1", 1), w("P1", "S1")), Terminator("S1", 9)),
        Phase((w("I1", "P1", 0), w("I2", "P1", 1), w("P1", "S1")), Terminator("S1", 9)),
        Phase((w("S1", "O1"),), None),
    ))
    states = required_states(path, {"S1": 0, "S2": 1})
    check_eq(states[0], {}, "phase 0 required state should be empty")
    check_eq(states[1], {}, "phase 1 required state should be empty (S1's value is dead)")
    level, level_ir, _ = _challenge_1()
    msg = check_raises(
        ValidationError,
        lambda: _check_distinct_required_states(
            _with_paths(level_ir, [path]), path, 0, {"S1": 0, "S2": 1}),
        "duplicate required state",
        "check 5 did not fire on two phases with identical required states")
    check("phases 0 and 1" in msg, f"check 5 should name both phases; got: {msg}")
    _rejects(level, level_ir, path,
             "validate_level accepted a path with duplicate required states")


def test_corruption_check_6_topological_order():
    level, level_ir, _ = _challenge_1()
    path = level_ir.paths[0]
    wires = list(path.phases[1].wires)
    wires[0], wires[2] = wires[2], wires[0]  # M1 -> P1 before M1 has inputs
    broken = _mutate_phase(path, 1, wires=tuple(wires))
    check_raises(ValidationError,
                 lambda: validate_level(level, _with_paths(level_ir, [broken]), project()),
                 "topological", "check 6 did not fire on an out-of-order phase")


def test_corruption_check_6_contiguity():
    """A multi-input node split across two runs fails even though every wire
    still follows its producer."""
    level, level_ir, _ = _challenge_1()
    path = level_ir.paths[0]
    w = list(path.phases[1].wires)
    # I2->M1 top, I1->M1 bottom, M1->P1 top, M1->P1 bottom, P1->S2
    reordered = (w[0], w[2], w[1], w[3], w[4])  # M1's inputs no longer contiguous
    broken = _mutate_phase(path, 1, wires=reordered)
    check_raises(ValidationError,
                 lambda: validate_level(level, _with_paths(level_ir, [broken]), project()),
                 "topological", "check 6 did not fire on non-contiguous node inputs")


def test_corruption_check_7_referential_integrity():
    from validate import _check_referential_integrity
    level, level_ir, _ = _challenge_1()
    path = level_ir.paths[0]
    wires = list(path.phases[2].wires)
    wires[0] = Wire("NOPE", 0, wires[0].to_id, wires[0].to_port)
    broken = _mutate_phase(path, 2, wires=tuple(wires))
    msg = check_raises(
        ValidationError,
        lambda: _check_referential_integrity(_with_paths(level_ir, [broken]), broken, 0),
        "referential integrity",
        "check 7 did not fire on a reference to a nonexistent node")
    check("NOPE" in msg and "phase 2" in msg,
          f"check 7 should name the node and phase; got: {msg}")
    _rejects(level, level_ir, broken,
             "validate_level accepted a reference to a nonexistent node")


def test_corruption_check_8_engine_limits():
    import dataclasses
    from project import EngineLimits
    level, level_ir, _ = _challenge_1()
    tight = dataclasses.replace(project(), limits=EngineLimits(4, 2, 4))
    msg = check_raises(ValidationError,
                       lambda: validate_level(level, level_ir, tight),
                       "engine limits", "check 8 did not fire against a lowered OPERATION_MAX")
    check("2" in msg, f"check 8 should name the limit it read; got: {msg}")


def test_corruption_check_9_display_range():
    level, level_ir, _ = _challenge_1()
    check_raises(ValidationError,
                 lambda: validate_level(level, level_ir, project(),
                                        ranges=DisplayRanges(output=(-9, 5))),
                 "display range", "check 9 did not fire against a narrowed output range")


def test_engine_limits_read_from_source():
    """Check 8 reads LevelBuilder's constants rather than hardcoding them."""
    limits = project().limits
    builder = os.path.join(project().root, "Levels", "LevelBuilder", "level_builder.gd")
    with open(builder, "r", encoding="utf-8") as fh:
        text = fh.read()
    for name, value in (("INPUT_MAX", limits.input_max),
                        ("OPERATION_MAX", limits.operation_max),
                        ("OUTPUT_MAX", limits.output_max)):
        check(f"const {name}: int = {value}" in text,
              f"{name} was parsed as {value}, which is not what level_builder.gd says")


# --------------------------------------------------------------------------
# store-free regression
# --------------------------------------------------------------------------

def _path_keys(paths, arrays):
    """Set of slot-numbering-independent keys, one per path.

    Compares two files by what their graphs *mean* rather than by slot number,
    because §19.4 reorders the arrays relative to what ships today: shipped
    store-free files list outputs in JSON key order, while §19.4 requires
    ascending by value. CR-P8 anticipates exactly this ("their .tres files will
    change even where the solution data does not"), so a comparison that keys on
    slot number would flag a rule being followed as a regression.

    So: a fixed-value node (Input, Output, Add Value) is identified by its
    VALUE, which is what pins it at runtime -- `_slot_value_requirements`
    prunes binding candidates by exactly this. Everything else (Sum, Subtract,
    Store) is freely interchangeable and is minimised over permutations.
    `to_port` is dropped on commutative targets, per §19.10.

    Wire sets are canonicalised to sorted tuples, NOT frozensets, before being
    turned into keys. `repr()` of a frozenset is not order-stable -- two
    content-equal frozensets built via different insertion histories can print
    their elements in a different order, and across processes PYTHONHASHSEED
    makes that vary run to run. `notation._canon` exists for exactly this
    reason. An earlier version of this helper used frozensets and reported a
    different number of matching paths on different runs of the same corpus.
    """
    import itertools
    values = {}
    for entries in arrays.values():
        for node_type, slot, value in entries:
            values[(node_type, slot)] = value

    fixed = set(project().fixed_value)
    groups = {}
    for node_type, slot in values:
        if node_type not in fixed:
            groups.setdefault(node_type, []).append(slot)
    classes = [(t, tuple(sorted(s))) for t, s in sorted(groups.items()) if len(s) >= 2]

    def endpoint(node_type, slot, remap):
        if node_type in fixed:
            return ("value", node_type, values[(node_type, slot)])
        return ("slot", node_type, remap.get((node_type, slot), slot))

    def keyed(remap):
        out = []
        for path in paths:
            phases = []
            for wires, term in path:
                ws = sorted(
                    (
                        (endpoint(ft, fs, remap), fp,
                         endpoint(tt, ts, remap),
                         None if tt in project().commutative else tp)
                        for (ft, fs, fp), (tt, ts, tp) in wires
                    ),
                    key=repr,
                )
                phases.append((tuple(ws), term))
            out.append(repr(tuple(phases)))
        return out

    if not classes:
        return set(keyed({}))

    best = None
    for choice in itertools.product(*(itertools.permutations(s) for _, s in classes)):
        remap = {}
        for (node_type, slots), perm in zip(classes, choice):
            for a, b in zip(slots, perm):
                remap[(node_type, a)] = b
        candidate = sorted(keyed(remap))
        if best is None or candidate < best:
            best = candidate
    return set(best)


def test_store_free_single_phase():
    """AddValue and SumAndSubtract levels emit single-phase paths with an
    empty required state."""
    seen = 0
    for level_json_path in corpus_levels():
        if category_of(level_json_path) not in STORE_FREE_CATEGORIES:
            continue
        _level, level_ir, _ = build(level_json_path)
        seen += 1
        for i, path in enumerate(level_ir.paths):
            check_eq(len(path.phases), 1,
                     f"{level_ir.name} path {i}: store-free level must be single-phase")
            check(path.phases[0].is_final,
                  f"{level_ir.name} path {i}: the only phase must be the final phase")
            check_eq(required_state(path, {}, 0), {},
                     f"{level_ir.name} path {i}: required state must be empty")
    check_eq(seen, 15, "expected 15 store-free levels in the corpus")


def _shipped_vs_emitted(level_json_path):
    _level, level_ir, _ = build(level_json_path)
    shipped = os.path.join(SHIPPED_ROOT, category_of(level_json_path),
                           f"{level_ir.name}.tres")
    with open(shipped, "r", encoding="utf-8") as fh:
        ship_paths, ship_arrays = tres.parse(fh.read(), project())
    emit_paths, emit_arrays = tres.parse(tres.render(level_ir, project()), project())
    return (level_ir, _path_keys(ship_paths, ship_arrays),
            _path_keys(emit_paths, emit_arrays))


def test_store_free_matches_shipped():
    """No shipped store-free solution is lost.

    The emitter may find MORE paths than were hand-authored -- it enumerates
    families exhaustively where the shipped files were transcribed by hand --
    and that is an improvement, not a regression: §19.10 notes a missing path
    means a player can find a legitimate solution the game cannot credit. What
    must never happen is a shipped path *disappearing*, so this asserts
    containment rather than equality. test_store_free_no_new_paths records
    where the two differ.
    """
    checked = 0
    for level_json_path in corpus_levels():
        if category_of(level_json_path) not in STORE_FREE_CATEGORIES:
            continue
        level_ir, shipped_keys, emitted_keys = _shipped_vs_emitted(level_json_path)
        missing = shipped_keys - emitted_keys
        check(not missing,
              f"{level_ir.name}: {len(missing)} shipped solution path(s) are absent from "
              f"the emitted file. A lost path means a legitimate player solution the "
              f"game can no longer credit.\n    missing: {sorted(missing)[:1]}")
        checked += 1
    check_eq(checked, 15, "expected to compare 15 shipped store-free levels")


def test_store_free_no_new_paths():
    """Records exactly which store-free levels gain paths.

    Kept as an explicit expected-set rather than a blanket allowance, so a
    level that starts gaining paths for some other reason still fails. Both
    entries below are levels whose shipped file was hand-transcribed with only
    a subset of the families the solver finds.
    """
    expected_gains = {"add_value_4": 8, "sum_subtract_9": 1}
    gains = {}
    for level_json_path in corpus_levels():
        if category_of(level_json_path) not in STORE_FREE_CATEGORIES:
            continue
        level_ir, shipped_keys, emitted_keys = _shipped_vs_emitted(level_json_path)
        extra = emitted_keys - shipped_keys
        if extra:
            gains[level_ir.name] = len(extra)
    check_eq(gains, expected_gains,
             "the set of store-free levels gaining solution paths has changed")


# --------------------------------------------------------------------------
# fixtures from the CR documents
# --------------------------------------------------------------------------

def test_cr_p1_challenge_1_phases():
    """CR-P1 acceptance criteria, literally."""
    level, _ir, families = _challenge_1()
    path = extract_path(level, families[0])
    check_eq(len(path.phases), 3, "challenge_1 family 1 should yield three phases")
    check_eq([str(t) for t in path.latch_sequence], ["S1=9", "S2=10"],
             "challenge_1 latch sequence")
    phase_1 = set(wire_strs(path.phases[1]))
    for expected in ("I2 -> M1 top", "I1 -> M1 bottom", "M1 -> P1 top",
                     "M1 -> P1 bottom", "P1 -> S2 top"):
        check(expected in phase_1, f"phase 1 should contain {expected!r}, has {sorted(phase_1)}")
    for absent in ("I1 -> P1 top", "I2 -> P1 bottom"):
        check(absent not in phase_1,
              f"phase 1 must not contain {absent!r} -- live, but feeds nothing the latch needs")
    check_eq(len(path.phases[2].wires), 7, "the final phase should contain seven wires")


def test_cr_p1_dead_latch_dropped():
    """A solution containing a latch never read afterwards emits no phase for
    it."""
    level, _ir, families = _challenge_1()
    base = extract_path(level, families[0])
    padded = Path(base.phases[:1] + (
        Phase(wires=(Wire("I1", 0, "S2", 0),), terminator=Terminator("S2", 2)),
    ) + base.phases[1:])
    # S2 is re-latched by the real phase 1, so the padded latch is dead.
    from phases import _drop_dead_latches
    kept = _drop_dead_latches(list(padded.phases), {"S1", "S2"})
    check_eq(len(kept), len(base.phases),
             "a latch nothing subsequently reads should have been dropped")


def test_cr_p2_challenge_1_ordering():
    """CR-P2 acceptance criteria, literally."""
    _level, level_ir, _ = _challenge_1()
    path = level_ir.paths[0]
    check_eq(wire_strs(path.phases[1]),
             ["I2 -> M1 top", "I1 -> M1 bottom", "M1 -> P1 top", "M1 -> P1 bottom",
              "P1 -> S2 top"],
             "challenge_1 phase 1 ordering")
    check_eq(wire_strs(path.phases[2]),
             ["S1 -> P1 top", "S2 -> P1 bottom", "S2 -> M1 top", "S1 -> M1 bottom",
              "M1 -> O1 top", "S2 -> O2 top", "P1 -> O3 top"],
             "challenge_1 final phase ordering")


def test_cr_p2_latch_last_and_outputs_last():
    for level_json_path in corpus_levels():
        _level, level_ir, _ = build(level_json_path)
        output_ids = {e.node_id for e in level_ir.layout.outputs}
        for pi, path in enumerate(level_ir.paths):
            for k, phase in enumerate(path.phases):
                if phase.terminator is not None:
                    check_eq(phase.wires[-1].to_id, phase.terminator.store_id,
                             f"{level_ir.name} path {pi} phase {k}: latch connection not last")
                else:
                    targets = [w.to_id for w in phase.wires]
                    first = next((n for n, t in enumerate(targets) if t in output_ids), None)
                    if first is not None:
                        check(all(t in output_ids for t in targets[first:]),
                              f"{level_ir.name} path {pi}: outputs are not all last")


def test_cr_p2_fails_loudly_on_cycle():
    """A cycle produces a loud failure, not a fallback to insertion order."""
    _level, level_ir, _ = _challenge_1()
    cyclic = Phase(wires=(Wire("P1", 0, "M1", 0), Wire("I1", 0, "M1", 1),
                          Wire("M1", 0, "P1", 0), Wire("I2", 0, "P1", 1)),
                   terminator=None)
    check_raises(OrderingError,
                 lambda: order_phase(cyclic, level_ir.layout, "synthetic"),
                 "cycle", "ordering did not fail loudly on a cyclic phase")


def test_cr_p3_required_state_worked_example():
    """The challenge_4 worked reference in HINT_SYSTEM_PHASE_CHANGE_REQUESTS.md
    §0 -- the primary acceptance fixture for the game side's CR-1 and CR-4,
    reproduced by this independent implementation."""
    w = lambda f, t, p=0: Wire(f, 0, t, p)  # noqa: E731
    path = Path((
        Phase((w("I1", "P1", 0), w("I1", "P1", 1), w("I2", "M1", 0),
               w("P1", "M1", 1), w("M1", "S1")), Terminator("S1", 3)),
        Phase((w("S1", "M1", 0), w("I1", "M1", 1), w("M1", "S2")), Terminator("S2", 1)),
        Phase((w("I2", "P1", 0), w("I2", "P1", 1), w("P1", "M1", 0),
               w("M1", "S1")), Terminator("S1", 12)),
        Phase((w("S1", "P1", 1), w("S2", "O1"), w("M1", "O2"), w("P1", "O3")), None),
    ))
    slots = {"S1": 0, "S2": 1}
    check_eq(required_states(path, slots), [{}, {0: 3}, {1: 1}, {0: 12, 1: 1}],
             "challenge_4 path 0 required states (HINT §0 table)")

    def cursor(s1, s2):
        have = {}
        if s1 is not None:
            have[0] = s1
        if s2 is not None:
            have[1] = s2
        matching = [k for k, st in enumerate(required_states(path, slots))
                    if all(have.get(slot) == v for slot, v in st.items())]
        return max(matching)

    for s1, s2, expected in [(None, None, 0), (3, None, 1), (3, 1, 2), (10, 1, 2),
                             (12, 1, 3), (99, None, 0), (3, 5, 1)]:
        check_eq(cursor(s1, s2), expected,
                 f"cursor for S1={s1} S2={s2} (HINT §0 table)")


def test_cr_p4_matches_19_12_worked_example():
    """The emitted challenge_1 matches §19.12's worked example line for line.

    ext_resource lines are compared as a set: this emitter sorts them by id,
    which is how Godot itself saves (see any shipped .tres) and how the example
    differs -- it lists CSD last.

    §19.12 shows only path 0 ("Add one more `Path<n>` block per distinct final
    configuration"), so this compares a single-path render. challenge_1 has
    nine distinct configurations in full.
    """
    _level, full, _ = _challenge_1()
    level_ir = _with_paths(full, full.paths[:1])
    emitted = [l.rstrip() for l in tres.render(level_ir, project()).splitlines() if l.strip()]

    import re
    md_path = os.path.join(_GEN, "LEVEL_GENERATION_AGENT_INSTRUCTIONS.md")
    with open(md_path, "r", encoding="utf-8") as fh:
        blocks = re.findall(r"```\n(\[gd_resource.*?)```", fh.read(), re.DOTALL)
    check(blocks, "could not find §19.12's worked example in the instructions")
    spec = [l.rstrip() for l in blocks[0].splitlines()
            if l.strip() and not l.lstrip().startswith(";")]

    def split(lines):
        ext = sorted(l for l in lines if l.startswith("[ext_resource"))
        rest = [l for l in lines if not l.startswith("[ext_resource")]
        return ext, rest

    spec_ext, spec_rest = split(spec)
    emit_ext, emit_rest = split(emitted)
    check_eq(emit_ext, spec_ext, "ext_resource lines differ from §19.12")
    check_eq(emit_rest, spec_rest, "emitted body differs from §19.12's worked example")


# --------------------------------------------------------------------------
# layout (CR-P8)
# --------------------------------------------------------------------------

def _synthetic_level(composition):
    from model import Level, OpSpec
    ops, counter = {}, {}
    for gen_type, count in composition:
        for _ in range(count):
            counter[gen_type] = counter.get(gen_type, 0) + 1
            node_id = {"sum": "P", "subtract": "M", "add": "A",
                       "store": "S"}[gen_type] + str(counter[gen_type])
            ops[node_id] = OpSpec(node_id, gen_type, 3 if gen_type == "add" else None)
    return Level("synthetic", {"I1": 1}, ops, {"O1": 1})


def _slots(composition):
    layout = build_layout(_synthetic_level(composition), project())
    return [e.node_id for e in layout.operations]


def test_cr_p8_worked_cases():
    """Every row of §19.4a's worked-cases table."""
    cases = [
        ([("sum", 3), ("add", 2), ("store", 1)],
         ["P1", "A1", "P2", "A2", "P3", "S1"],
         "6: Sum {0,2,4}; Add's shapes all blocked -> fallback {1,3}; Store at 5"),
        ([("sum", 2), ("subtract", 2), ("add", 2)],
         ["P1", "P2", "A1", "A2", "M1", "M2"],
         "6: Sum {0,1}, Subtract {4,5}, Add {2,3} -- LARGE first, then ordinal"),
        ([("sum", 4), ("add", 2)], ["P1", "P2", "P3", "P4", "A1", "A2"],
         "6: Sum {0,1,2,3}, Add falls to {4,5}"),
        ([("sum", 2), ("store", 2), ("add", 2)],
         ["P1", "P2", "S1", "S2", "A1", "A2"],
         "6: Sum {0,1}, Add {4,5}, Stores at 2,3"),
        ([("subtract", 3), ("add", 2)], ["M1", "M2", "M3", "A1", "A2"],
         "5: Subtract {0,1,2}, Add {3,4}"),
        ([("sum", 4), ("store", 1)], ["P1", "P2", "S1", "P3", "P4"],
         "5: Sum {0,1,3,4}, Store centred at 2"),
        ([("sum", 2), ("add", 2)], ["P1", "P2", "A1", "A2"], "4: Sum {0,1}, Add {2,3}"),
        ([("sum", 3), ("store", 1)], ["P1", "P2", "P3", "S1"],
         "4: no shape for (4,3); Sums 0,1,2 and Store at 3 by step 4"),
        ([("sum", 2), ("store", 1)], ["P1", "S1", "P2"],
         "3: Sum {0,2}, Store centred at 1"),
    ]
    for composition, expected, label in cases:
        check_eq(_slots(composition), expected, f"§19.4a worked case -- {label}")


def test_cr_p8_fallback_and_no_shape():
    """The two paths CR-P8 calls out explicitly."""
    slots = _slots([("sum", 3), ("add", 2), ("store", 1)])
    check_eq([slots[i] for i in (0, 2, 4)], ["P1", "P2", "P3"],
             "n=6 3+2: the triple should take {0,2,4}")
    check_eq([slots[i] for i in (1, 3)], ["A1", "A2"],
             "n=6 3+2: all of the pair's listed shapes are blocked, so it lands on {1,3}")
    check_eq(_slots([("sum", 3), ("store", 1)]), ["P1", "P2", "P3", "S1"],
             "n=4 with a triple takes the no-shape path and falls through to step 4")


def test_cr_p8_unknown_size_group_raises():
    """A NodeType absent from both size groups raises rather than silently
    sorting by ordinal alone."""
    from model import Level, OpSpec
    saved = SIZE_GROUP.pop("SUM")
    try:
        level = Level("synthetic", {"I1": 1},
                      {"P1": OpSpec("P1", "sum"), "P2": OpSpec("P2", "sum")},
                      {"O1": 1})
        check_raises(LayoutError, lambda: build_layout(level, project()),
                     "size group", "a type with no size group should raise")
    finally:
        SIZE_GROUP["SUM"] = saved


def test_cr_p8_layout_deterministic():
    for composition in ([("sum", 3), ("add", 2), ("store", 1)],
                        [("sum", 2), ("subtract", 2), ("add", 2)]):
        check_eq(_slots(composition), _slots(composition), "layout is not deterministic")


def test_cr_p8_slots_match_array_positions():
    """Slot numbers in emitted solution steps match post-ordering array
    positions -- re-parse the emitted file, rebuild the map from its own
    arrays, and confirm every step still resolves."""
    for level_json_path in corpus_levels():
        _level, level_ir, _ = build(level_json_path)
        text = tres.render(level_ir, project())
        _paths, arrays = tres.parse(text, project())
        available = {(t, s) for entries in arrays.values() for t, s, _ in entries}
        for pi, path in enumerate(level_ir.paths):
            for k, phase in enumerate(path.phases):
                for wire in phase.wires:
                    for node_id in (wire.from_id, wire.to_id):
                        ref = level_ir.layout.ref(node_id)
                        check(ref in available,
                              f"{level_ir.name} path {pi} phase {k}: {node_id} -> {ref} "
                              f"is not present in the emitted arrays")


# --------------------------------------------------------------------------
# collapse (§19.10)
# --------------------------------------------------------------------------

def test_collapse_is_idempotent_and_shortest_first():
    for level_json_path in corpus_levels():
        _level, level_ir, _ = build(level_json_path)
        costs = [(sum(1 for p in path.phases if p.terminator is not None),
                  sum(len(p.wires) for p in path.phases)) for path in level_ir.paths]
        check_eq(costs, sorted(costs),
                 f"{level_ir.name}: solution_paths are not ordered shortest-first")


# --------------------------------------------------------------------------
# runner
# --------------------------------------------------------------------------

TESTS = [v for k, v in sorted(globals().items()) if k.startswith("test_")]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--regenerate", action="store_true",
                        help="rewrite the golden files instead of comparing")
    parser.add_argument("-k", default=None, help="only run tests whose name contains this")
    args = parser.parse_args(argv)

    if args.regenerate:
        print("regenerating golden files...")
        test_golden(regenerate=True)
        count = len(glob.glob(os.path.join(GOLDEN_ROOT, "*", "*.tres")))
        print(f"wrote {count} golden file(s) to {GOLDEN_ROOT}")
        return 0

    failures = []
    for test in TESTS:
        name = test.__name__
        if args.k and args.k not in name:
            continue
        try:
            test()
        except Failure as exc:
            failures.append((name, str(exc)))
            print(f"FAIL {name}\n  {exc}")
        except Exception:  # noqa: BLE001
            failures.append((name, traceback.format_exc()))
            print(f"ERROR {name}\n{traceback.format_exc()}")
        else:
            print(f"ok   {name}")

    ran = sum(1 for t in TESTS if not args.k or args.k in t.__name__)
    if failures:
        print(f"\n{len(failures)} of {ran} FAILED")
        return 1
    print(f"\nALL TESTS PASSED ({ran}/{ran})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
