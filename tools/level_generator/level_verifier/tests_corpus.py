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
        desc="I1=3; A1=+2, S1=s, S2=s; O1=11  (leftover scratch must not split a family)",
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
        # Exactly two, distinguished by WHICH VALUE THE FINAL NETWORK READS:
        #   {9}   ratchet to 9, then A1 computes 9+2=11 live
        #   {11}  latch the 11 itself, then wire it straight out
        # Both leave a value in the other store (7 and 9 respectively) that
        # nothing reads at the end.
        #
        # Characterisation only: this level has one route per end state, so it
        # passes under both the old and the fixed signature in
        # notation._final_state_and_wiring. Case 7 is the one that actually
        # fails without the fix.
        expect_families=2,
        expect_final_read_store_values=[[9], [11]],
    ),
    dict(
        num=7,
        desc="I1=1; A1=+2, A2=+5, S1=s, S2=s; O1=11  (two routes to 11, different scratch)",
        data={
            "name": "case7",
            "inputs": {"I1": 1},
            "operations": {
                "A1": {"type": "add", "value": 2},
                "A2": {"type": "add", "value": 5},
                "S1": {"type": "store"},
                "S2": {"type": "store"},
            },
            "outputs": {"O1": 11},
        },
        expect_solvable=True,
        # Deliberately NOT minimal -- either Add alone can ratchet to 11, so
        # each is individually deletable. Minimality is not what this case
        # tests; it is here because it is the smallest shape that reaches one
        # stored value by two routes leaving different scratch behind.
        expect_minimal=False,
        # Three families, by what the final network reads: 6, 9, or 11.
        # Without the fix in notation._final_state_and_wiring this is FOUR,
        # because the two ways of ending with 11 stored -- leftover 6 in one
        # store versus leftover 9 in the other -- count as different families
        # despite being the same solution to a player: only the 11 is wired to
        # anything. This case fails on the pre-fix signature.
        expect_families=3,
        expect_final_read_store_values=[[6], [9], [11]],
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

        # The store values the FINAL network reads, per family, sorted. Guards
        # the rule that leftover scratch in an unread store must not split one
        # solution into several families.
        expected_read = case.get("expect_final_read_store_values")
        if expected_read is not None:
            got = []
            for sol in families:
                held = {l.store_id: l.value for l in sol.latches}
                read = {p for n in sol.final.built for p in n.inputs if p in held}
                read |= {v for v in sol.final.assignment.values() if v in held}
                got.append(sorted(held[s] for s in read))
            got.sort()
            if got != sorted(expected_read):
                ok = False
                msgs.append(
                    f"final-network-read store values per family are {got}, "
                    f"expected {sorted(expected_read)} -- an unread leftover value "
                    f"is probably splitting one solution into several families"
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
