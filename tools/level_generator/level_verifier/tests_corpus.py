"""
Regression corpus from the build spec, section 8. `verify --test` runs this.
"""
from model import level_from_dict
from solver import solve
from notation import dedupe_families, render_solution
from minimality import minimality_report

DEFAULT_BOUND = (-200, 200)
DEFAULT_MAX_LATCHES = 12

CASES = [
    dict(
        num=1,
        desc="I1=3; A1=+3, P1=+; O1=12",
        data={
            "name": "case1",
            "inputs": {"I1": 3},
            "operations": {"A1": {"type": "add", "value": 3}, "P1": {"type": "sum"}},
            "outputs": {"O1": 12},
        },
        expect_solvable=True,
        expect_minimal=True,
    ),
    dict(
        num=2,
        desc="I1=1; A1=+1, S1=s; O1=2, O2=3",
        data={
            "name": "case2",
            "inputs": {"I1": 1},
            "operations": {"A1": {"type": "add", "value": 1}, "S1": {"type": "store"}},
            "outputs": {"O1": 2, "O2": 3},
        },
        expect_solvable=True,
        expect_minimal=True,
    ),
    dict(
        num=3,
        desc="I1=3; A1=+3, S1=s; O1=12  (single-store deadlock -- must be UNSOLVABLE)",
        data={
            "name": "case3",
            "inputs": {"I1": 3},
            "operations": {"A1": {"type": "add", "value": 3}, "S1": {"type": "store"}},
            "outputs": {"O1": 12},
        },
        expect_solvable=False,
        expect_minimal=None,
    ),
    dict(
        num=4,
        desc="I1=3; A1=+3, S1=s, S2=s; O1=12  (two-store ratchet)",
        data={
            "name": "case4",
            "inputs": {"I1": 3},
            "operations": {
                "A1": {"type": "add", "value": 3},
                "S1": {"type": "store"},
                "S2": {"type": "store"},
            },
            "outputs": {"O1": 12},
        },
        expect_solvable=True,
        expect_minimal=True,
    ),
    dict(
        num=5,
        desc="I1=2, I2=7; P1=+, M1=-, S1=s, S2=s; O1=1, O2=17, O3=19",
        data={
            "name": "case5",
            "inputs": {"I1": 2, "I2": 7},
            "operations": {
                "P1": {"type": "sum"},
                "M1": {"type": "subtract"},
                "S1": {"type": "store"},
                "S2": {"type": "store"},
            },
            "outputs": {"O1": 1, "O2": 17, "O3": 19},
        },
        expect_solvable=True,
        expect_minimal=True,
        expect_min_families=2,
    ),
    dict(
        num=6,
        desc="I1=3; A1=+2, S1=s, S2=s; O1=11  (must NOT latch past the finish)",
        data={
            "name": "case6",
            "inputs": {"I1": 3},
            "operations": {
                "A1": {"type": "add", "value": 2},
                "S1": {"type": "store"},
                "S2": {"type": "store"},
            },
            "outputs": {"O1": 11},
        },
        expect_solvable=True,
        expect_minimal=True,
        # Exactly one family. The ratchet reaches S1=9, at which point A1 holds
        # 11 and can be wired straight to O1. A second family used to come back
        # that latched that same 11 into S2 and then read it back out --
        # every latch "used", so the dead-latch sweep kept it, but it is pure
        # padding and no player would do it. See _latches_past_the_finish.
        expect_families=1,
        expect_max_latches_in_any_family=3,
    ),
]


def run_all(verbose=True):
    all_pass = True
    for case in CASES:
        ok, detail = run_one(case, verbose=verbose)
        all_pass = all_pass and ok
    print("")
    print("ALL TESTS PASSED" if all_pass else "SOME TESTS FAILED")
    return all_pass


def run_one(case, verbose=True):
    level = level_from_dict(case["data"])
    result = solve(level, bound=DEFAULT_BOUND, max_latches=DEFAULT_MAX_LATCHES,
                    find_all=True, max_families=10)
    ok = True
    msgs = []

    if result.solvable != case["expect_solvable"]:
        ok = False
        msgs.append(f"solvable={result.solvable}, expected={case['expect_solvable']}")

    if case["expect_solvable"] and result.solvable:
        is_minimal, rows = minimality_report(level, DEFAULT_BOUND, DEFAULT_MAX_LATCHES)
        if case.get("expect_minimal") is not None and is_minimal != case["expect_minimal"]:
            ok = False
            msgs.append(f"minimal={is_minimal}, expected={case['expect_minimal']}")
            for node_id, required, exhausted in rows:
                if not required:
                    msgs.append(f"    node {node_id} not required (deletable)")

        families = dedupe_families(level, result.solutions)
        min_fam = case.get("expect_min_families")
        if min_fam is not None and len(families) < min_fam:
            ok = False
            msgs.append(f"found {len(families)} distinct solution families, expected >= {min_fam}")

        exact_fam = case.get("expect_families")
        if exact_fam is not None and len(families) != exact_fam:
            ok = False
            msgs.append(f"found {len(families)} distinct solution families, expected exactly {exact_fam}")

        # Guards against padded families creeping back in: a solution that
        # keeps latching after the level is already finishable inflates this
        # without changing what the level can do.
        max_latches_seen = case.get("expect_max_latches_in_any_family")
        if max_latches_seen is not None:
            worst = max((len(s.latches) for s in families), default=0)
            if worst > max_latches_seen:
                ok = False
                msgs.append(
                    f"a family uses {worst} latches, expected at most {max_latches_seen} "
                    f"-- a solution is latching past the point the level could be finished"
                )

    status = "PASS" if ok else "FAIL"
    if verbose:
        print(f"[{status}] Case {case['num']}: {case['desc']}")
        for m in msgs:
            print(f"        {m}")
        if case["expect_solvable"] and result.solvable and verbose:
            families = dedupe_families(level, result.solutions)
            print(f"        -> {len(families)} distinct family/families found")
            for i, sol in enumerate(families, 1):
                print(f"        Family {i}:")
                for line in render_solution(level, sol):
                    print(f"          {line}")
    return ok, msgs


if __name__ == "__main__":
    run_all()
