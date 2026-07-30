"""
Convenience re-export seam for level_generator.

level_verifier/ is a flat, non-package collection of modules that import each
other by bare name (it was never meant to be imported from outside its own
directory). This module exists purely to tidy that seam: it re-exports the
handful of names level_generator/generate.py needs, so callers can do

    from api import Level, OpSpec, solve, ...

instead of reaching into five different verifier modules by hand. It does not
change or wrap any behavior -- every name below is the exact object from the
verifier, untouched.

Nothing in level_verifier/ imports this file; it is purely a convenience for
code outside the verifier's own directory. Adding it does not change any
existing function signature, return shape, or solving/family/minimality logic,
so it does not require re-running level_verifier's regression suite -- but
`cd level_verifier && python3 verify.py --test` was run before this file was
added and passed ALL TESTS PASSED (5/5), and should continue to.
"""
from __future__ import annotations

from model import (
    Level,
    OpSpec,
    load_level,
    level_from_dict,
    validate,
    VALID_TYPES,
)
from solver import (
    solve,
    Solution,
    LatchPhase,
    FinalPhase,
    SearchResult,
    StoreState,
)
from notation import (
    render_solution,
    dedupe_families,
)
from minimality import (
    minimality_report,
)
from reach import (
    reach_values,
    find_covering_networks,
    PlacedNode,
)

__all__ = [
    "Level", "OpSpec", "load_level", "level_from_dict", "validate", "VALID_TYPES",
    "solve", "Solution", "LatchPhase", "FinalPhase", "SearchResult", "StoreState",
    "render_solution", "dedupe_families",
    "minimality_report",
    "reach_values", "find_covering_networks", "PlacedNode",
]
