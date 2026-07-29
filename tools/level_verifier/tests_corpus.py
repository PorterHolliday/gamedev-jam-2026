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

        families = dedupe_families(result.solutions)
        min_fam = case.get("expect_min_families")
        if min_fam is not None and len(families) < min_fam:
            ok = False
            msgs.append(f"found {len(families)} distinct solution families, expected >= {min_fam}")

    status = "PASS" if ok else "FAIL"
    if verbose:
        print(f"[{status}] Case {case['num']}: {case['desc']}")
        for m in msgs:
            print(f"        {m}")
        if case["expect_solvable"] and result.solvable and verbose:
            families = dedupe_families(result.solutions)
            print(f"        -> {len(families)} distinct family/families found")
            for i, sol in enumerate(families, 1):
                print(f"        Family {i}:")
                for line in render_solution(level, sol):
                    print(f"          {line}")
    return ok, msgs


if __name__ == "__main__":
    run_all()
