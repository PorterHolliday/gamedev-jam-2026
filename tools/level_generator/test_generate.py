#!/usr/bin/env python3
"""
Regression tests for level_generator/generate.py.

These are the generator's OWN tests -- separate from level_verifier's
regression corpus (level_verifier/tests_corpus.py, run via
`cd level_verifier && python3 verify.py --test`), which this file never
touches or depends on beyond importing the verifier as a library, same as
generate.py itself does.

Run with:
    python3 test_generate.py

Exit code 0 and "ALL TESTS PASSED" on success, matching the verifier's own
convention; nonzero and a failure list otherwise.
"""
from __future__ import annotations

import os
import sys
import traceback

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(_HERE, "level_verifier"))

import generate as g  # noqa: E402
from model import level_from_dict  # noqa: E402
from solver import solve  # noqa: E402
from minimality import minimality_report  # noqa: E402


FAILURES = []


def check(name, condition, detail=""):
    if not condition:
        FAILURES.append(f"{name}: {detail}")
        print(f"  FAIL: {name}  {detail}")
    else:
        print(f"  ok:   {name}")


def run_test(fn):
    print(f"\n=== {fn.__name__} ===")
    try:
        fn()
    except Exception:
        FAILURES.append(f"{fn.__name__}: raised an exception")
        print(f"  FAIL: {fn.__name__} raised an exception")
        traceback.print_exc()


# --------------------------------------------------------------------------
# Pipeline A: deletion always yields a minimality_report-confirmed level
# --------------------------------------------------------------------------

def test_deletion_produces_minimal_levels():
    seeds = [1, 2, 3]
    budget = g.SolveBudget(bound=(-20, 20), max_latches=6, timeout=4)
    for seed in seeds:
        outputs = g.make_output_dict([1, 17, 19] if seed % 2 else [3, -8, 12])
        result = g.generate_by_deletion(outputs, pool_inputs=3, pool_ops=4, seed=seed,
                                         budget=budget, max_resamples=50)
        check(f"deletion seed={seed} found a candidate", result is not None)
        if result is None:
            continue
        level = result["level"]

        r = solve(level, bound=budget.bound, max_latches=budget.max_latches, find_all=False)
        check(f"deletion seed={seed} level is solvable", r.solvable,
              f"solve() reported solvable={r.solvable}")

        is_minimal, rows = minimality_report(level, budget.bound, budget.max_latches)
        check(f"deletion seed={seed} level is minimal (independent oracle check)", is_minimal,
              f"rows={rows}")


# --------------------------------------------------------------------------
# Generated levels load cleanly and respect design constraints
# --------------------------------------------------------------------------

def test_generated_levels_load_cleanly_with_no_warnings():
    budget = g.SolveBudget(bound=(-20, 20), max_latches=6, timeout=4)
    outputs = g.make_output_dict([2, 6, -9])
    result = g.generate_by_deletion(outputs, pool_inputs=3, pool_ops=4, seed=7,
                                     budget=budget, max_resamples=50)
    check("found a deletion candidate for load-cleanliness test", result is not None)
    if result is None:
        return
    level = result["level"]
    data = g.level_to_dict(level)
    reloaded = level_from_dict(data)
    check("reloaded level has zero design-constraint warnings", reloaded.warnings == [],
          f"warnings={reloaded.warnings}")
    check("reloaded level has 1-4 inputs", 1 <= len(reloaded.inputs) <= 4,
          f"got {len(reloaded.inputs)}")
    check("reloaded level has 1-6 operations", 1 <= len(reloaded.operations) <= 6,
          f"got {len(reloaded.operations)}")
    check("reloaded level input values distinct",
          len(set(reloaded.inputs.values())) == len(reloaded.inputs))
    check("reloaded level output values distinct",
          len(set(reloaded.outputs.values())) == len(reloaded.outputs))


# --------------------------------------------------------------------------
# Generated levels are always solvable per solve()
# --------------------------------------------------------------------------

def test_generated_levels_are_solvable():
    budget = g.SolveBudget(bound=(-20, 20), max_latches=6, timeout=4)
    configs = [
        ([1, 17, 19], 3, 4, 11),
        ([5, -3], 2, 3, 22),
    ]
    for outputs_vals, pool_inputs, pool_ops, seed in configs:
        outputs = g.make_output_dict(outputs_vals)
        result = g.generate_by_deletion(outputs, pool_inputs, pool_ops, seed, budget,
                                         max_resamples=50)
        check(f"candidate found for outputs={outputs_vals}", result is not None)
        if result is None:
            continue
        level = result["level"]
        r = solve(level, bound=budget.bound, max_latches=budget.max_latches, find_all=False)
        check(f"generated level for outputs={outputs_vals} solves", r.solvable)


# --------------------------------------------------------------------------
# Isomorphism filter
# --------------------------------------------------------------------------

def test_isomorphism_filter_identifies_known_pairs():
    f = g.IsomorphismFilter()

    base = g.Level("base", {"I1": 3, "I2": 7},
                    {"P1": g.OpSpec("P1", "sum"), "M1": g.OpSpec("M1", "subtract")},
                    {"O1": 10})
    relabeled = g.Level("relabeled", {"I1": 3, "I2": 7},
                         {"M1": g.OpSpec("M1", "sum"), "P1": g.OpSpec("P1", "subtract")},
                         {"O1": 10})
    different_multiset = g.Level("diff", {"I1": 3, "I2": 7},
                                  {"P1": g.OpSpec("P1", "sum"), "P2": g.OpSpec("P2", "sum")},
                                  {"O1": 10})
    same_add_value = g.Level("same_add", {"I1": 3},
                              {"A1": g.OpSpec("A1", "add", 5), "A2": g.OpSpec("A2", "add", 5)},
                              {"O1": 8})
    diff_add_value = g.Level("diff_add", {"I1": 3},
                              {"A1": g.OpSpec("A1", "add", 5), "A2": g.OpSpec("A2", "add", 6)},
                              {"O1": 8})

    check("first level is always new", f.is_new(base))
    check("relabeled (same type/value multiset) level is NOT new -- isomorphic",
          not f.is_new(relabeled))
    check("different op multiset level IS new -- not isomorphic", f.is_new(different_multiset))
    check("two add nodes with same value is a distinct signature", f.is_new(same_add_value))
    check("two add nodes with different values is a distinct signature", f.is_new(diff_add_value))

    f2 = g.IsomorphismFilter()
    check("canonical_signature is symmetric under relabeling",
          f2.is_new(relabeled) and not f2.is_new(base))


# --------------------------------------------------------------------------
# Trivial-output post-filter
# --------------------------------------------------------------------------

def test_trivial_output_filter():
    trivial = g.Level("t", {"I1": 5, "I2": 9}, {}, {"O1": 5})
    nontrivial = g.Level("n", {"I1": 5, "I2": 9}, {}, {"O1": 14})
    check("output equal to an input value is flagged trivial", g.has_trivial_output(trivial))
    check("output not matching any input is not flagged trivial",
          not g.has_trivial_output(nontrivial))


# --------------------------------------------------------------------------
# runner
# --------------------------------------------------------------------------

def run_all() -> bool:
    tests = [
        test_deletion_produces_minimal_levels,
        test_generated_levels_load_cleanly_with_no_warnings,
        test_generated_levels_are_solvable,
        test_isomorphism_filter_identifies_known_pairs,
        test_trivial_output_filter,
    ]
    for t in tests:
        run_test(t)

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILURE(S):")
        for f in FAILURES:
            print(f"  - {f}")
        return False
    print("ALL TESTS PASSED")
    return True


if __name__ == "__main__":
    ok = run_all()
    sys.exit(0 if ok else 1)
