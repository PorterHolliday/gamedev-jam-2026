#!/usr/bin/env python3
"""
CR-P5 -- one command from an approved level JSON to a loadable `.tres`.

    python3 emit.py levels/Challenge/challenge_4.json --category Challenge

Stages: solve via level_verifier/api.py -> collapse families to distinct final
configurations (§19.10) keeping the shortest journey per class -> extract
phases (CR-P1) -> order (CR-P2) -> validate (CR-P3) -> serialise (CR-P4) ->
write.

WHAT THIS TOOL DOES NOT DO
--------------------------
It does not choose levels, assign tiers, or decide what is interesting. That
stays with the curating agent (§16). The contract here is: given an approved
level JSON, produce a correct `.tres` or fail loudly.

It does not edit `Singletons/LevelManager/level_manager.tscn`. Getting a level
playable requires adding the resource to `LevelManager.level_data_list`, and
this tool prints the exact lines to paste rather than editing the scene.
Programmatic `.tscn` editing is the one step in this pipeline with a real
corruption risk and no validation available short of opening the editor; the
manual paste is seconds of work against that. Revisit if it becomes a
bottleneck at volume.

WHERE OUTPUT GOES
-----------------
By default, a staging directory (`emitted/`) rather than the game project.
The phased `.tres` format is not readable by the shipped hint system until
HINT_SYSTEM_PHASE_CHANGE_REQUESTS.md CR-1..CR-6 land -- writing phased files
into `math-machine/Levels/LevelData/` before then would leave store levels
unplayable. Pass `--in-project` once the game side is ready; that targets
`math-machine/Levels/LevelData/<Category>/` as CR-P5 specifies.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "emitter"))
sys.path.insert(0, os.path.join(_HERE, "level_verifier"))

from api import dedupe_families, load_level, solve  # noqa: E402
from collapse import collapse_paths  # noqa: E402
from ir import LevelIR  # noqa: E402
from layout import build_layout, LayoutError  # noqa: E402
from ordering import order_paths, OrderingError  # noqa: E402
from phases import extract_paths, PhaseExtractionError  # noqa: E402
from project import load_project, ProjectReadError, DEFAULT_PROJECT_ROOT  # noqa: E402
from validate import validate_level, DisplayRanges, DEFAULT_RANGES, ValidationError  # noqa: E402
import tres  # noqa: E402

DEFAULT_STAGING = os.path.join(_HERE, "emitted")
IN_PROJECT_ROOT = os.path.normpath(
    os.path.join(_HERE, "..", "..", "math-machine", "Levels", "LevelData")
)

DEFAULT_BOUND = (-20, 20)
DEFAULT_MAX_LATCHES = 8


class EmitError(RuntimeError):
    pass


def _parse_bound(text: str):
    try:
        lo, hi = (int(p) for p in text.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"--bound expects lo,hi (got {text!r}). Note the =-form is required "
            f"when lo is negative: --bound=-20,20"
        ) from None
    return (lo, hi)


def solve_params(level_json_path: str, args):
    """Solve bound and latch limit, from the flags if given, else from the
    level's own recorded `source` block, else the defaults.

    Preferring the level's recorded values matters: §19.0 gate 5 requires a
    transcript captured "at its own recorded bound", and silently solving at a
    different one would produce a correct-looking file for a different level.
    """
    with open(level_json_path, "r", encoding="utf-8") as fh:
        raw = json.load(fh)
    source = raw.get("source", {}) or {}
    bound = args.bound or tuple(source.get("bound") or DEFAULT_BOUND)
    max_latches = args.max_latches or int(source.get("max_latches") or DEFAULT_MAX_LATCHES)
    return (int(bound[0]), int(bound[1])), max_latches


def display_ranges(args) -> DisplayRanges:
    return DisplayRanges(
        input=args.input_range or DEFAULT_RANGES.input,
        output=args.output_range or DEFAULT_RANGES.output,
        add_value=args.add_value_range or DEFAULT_RANGES.add_value,
    )


def build(level_json_path: str, project, args):
    level = load_level(level_json_path)
    bound, max_latches = solve_params(level_json_path, args)

    result = solve(level, bound=bound, max_latches=max_latches,
                   find_all=True, max_families=args.max_families)
    if not result.solvable:
        raise EmitError(
            f"{level.name}: no solution found at bound {bound} with max_latches "
            f"{max_latches}. Nothing was written."
        )
    families = dedupe_families(level, result.solutions)

    layout = build_layout(level, project)
    paths = extract_paths(level, families)
    paths = collapse_paths(paths, layout, project)
    paths = order_paths(paths, layout, level.name)

    level_ir = LevelIR(
        name=level.name,
        layout=layout,
        paths=tuple(paths),
        family_count=len(families),
        bound=bound,
        max_latches=max_latches,
    )
    validate_level(level, level_ir, project, ranges=display_ranges(args))
    return level, level_ir


def registration_snippet(res_path: str, uid) -> str:
    """The exact `ExtResource` line and array entry for the designer to paste
    into `Singletons/LevelManager/level_manager.tscn`.

    A new file has no uid yet -- Godot assigns one on first import and fills it
    into the reference on next save. The path-only form loads correctly in the
    meantime.
    """
    uid_attr = f' uid="{uid}"' if uid else ""
    ext_id = "N_new"
    return (
        f"  1. Add to the ext_resource block near the top of "
        f"Singletons/LevelManager/level_manager.tscn:\n\n"
        f'     [ext_resource type="Resource"{uid_attr} path="{res_path}" id="{ext_id}"]\n\n'
        f"  2. Append to level_data_list on the LevelManager node, in play order:\n\n"
        f'     ExtResource("{ext_id}")\n\n'
        f"     (Renumber `{ext_id}` to match the file's existing id convention.)"
        + ("" if uid else "\n     No uid yet -- Godot assigns one on first import.")
    )


def report(level_ir, out_path: str, uid, wrote: bool) -> str:
    lines = [
        f"{level_ir.name}",
        f"  file           : {out_path}" + ("" if wrote else "   [NOT WRITTEN]"),
        f"  solve          : bound {level_ir.bound[0]},{level_ir.bound[1]}  "
        f"max_latches {level_ir.max_latches}",
        f"  families       : {level_ir.family_count} -> {len(level_ir.paths)} "
        f"distinct final configuration(s)",
    ]
    if level_ir.family_count > len(level_ir.paths):
        lines.append(
            f"                   ({level_ir.family_count - len(level_ir.paths)} collapsed; "
            f"a large collapse may mean the level is less rich than its "
            f"solution_family_count suggested -- curation-relevant, §16)"
        )
    for i, path in enumerate(level_ir.paths):
        latches = " -> ".join(str(t) for t in path.latch_sequence) or "no latches"
        lines.append(
            f"  path {i}         : {len(path.phases)} phase(s), {latches}, "
            f"{sum(len(p.wires) for p in path.phases)} connections"
        )
    lines.append(f"  header uid     : {uid or '(none -- Godot assigns on first import)'}")
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Emit a Godot LevelData .tres from an approved level JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("level", nargs="+", help="path(s) to level JSON")
    parser.add_argument("--category", default=None,
                        help="subfolder under the output root (e.g. Challenge). "
                             "Defaults to the level JSON's own parent directory name.")
    parser.add_argument("--out-root", default=None,
                        help=f"output root (default: {DEFAULT_STAGING})")
    parser.add_argument("--in-project", action="store_true",
                        help="write into math-machine/Levels/LevelData/<Category>/ "
                             "instead of the staging directory. Only correct once the "
                             "game-side hint CRs have landed.")
    parser.add_argument("--project-root", default=DEFAULT_PROJECT_ROOT,
                        help="Godot project root (for UIDs, ordinals, engine limits)")
    parser.add_argument("--force", action="store_true", help="overwrite an existing file")
    parser.add_argument("--bound", type=_parse_bound, default=None,
                        help="solver bound lo,hi (default: the level's recorded bound). "
                             "Use the =-form for a negative low: --bound=-20,20")
    parser.add_argument("--max-latches", type=int, default=None,
                        help="latch limit (default: the level's recorded max_latches)")
    parser.add_argument("--max-families", type=int, default=20)
    # §9's three independently configurable ranges. Defaults are §9's defaults,
    # so check 9 fires unless a widening is asked for explicitly. Same =-form
    # trap as --bound: use --output-range=-10,20 for a negative low.
    parser.add_argument("--input-range", type=_parse_bound, default=None,
                        help="display range for input values (default: -9,9)")
    parser.add_argument("--output-range", type=_parse_bound, default=None,
                        help="display range for output targets (default: -20,20)")
    parser.add_argument("--add-value-range", type=_parse_bound, default=None,
                        help="display range for Add Value offsets (default: -9,9)")
    parser.add_argument("--stdout", action="store_true",
                        help="print the resource text instead of writing it")
    args = parser.parse_args(argv)

    if args.out_root and args.in_project:
        parser.error("--out-root and --in-project are mutually exclusive")
    out_root = args.out_root or (IN_PROJECT_ROOT if args.in_project else DEFAULT_STAGING)

    try:
        project = load_project(args.project_root)
    except ProjectReadError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3

    failures = 0
    reports = []
    for level_json_path in args.level:
        category = args.category or os.path.basename(
            os.path.dirname(os.path.abspath(level_json_path))
        )
        try:
            level, level_ir = build(level_json_path, project, args)
        except (EmitError, LayoutError, OrderingError, PhaseExtractionError,
                ValidationError, ProjectReadError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            failures += 1
            continue

        out_path = os.path.join(out_root, category, f"{level_ir.name}.tres")
        uid = tres.existing_header_uid(out_path)
        if uid is None and not args.in_project:
            # Regenerating a level that already ships: carry its uid so
            # level_manager.tscn's reference stays valid.
            shipped = os.path.join(IN_PROJECT_ROOT, category, f"{level_ir.name}.tres")
            uid = tres.existing_header_uid(shipped)

        text = tres.render(level_ir, project, uid=uid)

        if args.stdout:
            print(text)
            reports.append(report(level_ir, out_path, uid, wrote=False))
            continue

        if os.path.exists(out_path) and not args.force:
            print(
                f"error: {out_path} already exists. Re-run with --force to overwrite.",
                file=sys.stderr,
            )
            failures += 1
            continue

        tres.write(out_path, text)
        reports.append(report(level_ir, out_path, uid, wrote=True))
        res_path = "res://Levels/LevelData/%s/%s.tres" % (category, level_ir.name)
        reports.append(
            "\n  LevelManager registration (manual -- this tool does not edit .tscn):\n"
            + registration_snippet(res_path, uid)
        )

    if reports:
        print("\n".join(reports))
    if failures:
        print(f"\n{failures} level(s) failed; nothing was written for them.", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
