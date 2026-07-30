#!/usr/bin/env python3
"""
verify -- level verifier for the node-puzzle game.

Usage:
  verify level.json                 # full report: solvable, solution, minimality
  verify level.json --solve         # first solution only
  verify level.json --all           # every distinct solution family
  verify level.json --minimality    # leave-one-out table only
  verify level.json --bound 500 --max-latches 16
  verify --test                     # run the regression corpus

Exit codes: 0 = solvable and minimal; 1 = unsolvable (within bound); 2 = solvable
but not minimal.
"""
import argparse
import sys

from model import load_level
from report import full_report, solve_only_report, all_report, minimality_only_report


def parse_bound(s):
    parts = s.split(",")
    if len(parts) == 2:
        return (int(parts[0]), int(parts[1]))
    v = int(s)
    return (-v, v)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="verify", description="Node-puzzle level verifier")
    parser.add_argument("level", nargs="?", help="Path to a level JSON file")
    parser.add_argument("--solve", action="store_true", help="Print the first solution only")
    parser.add_argument("--all", action="store_true", help="Print every distinct solution family")
    parser.add_argument("--minimality", action="store_true", help="Print the leave-one-out table only")
    parser.add_argument("--bound", type=str, default="200",
                         help="Value bound: a single N for [-N,N], or 'lo,hi'. Default: 200")
    parser.add_argument("--max-latches", type=int, default=12, help="Max store-latch events to search. Default: 12")
    parser.add_argument("--max-families", type=int, default=10,
                         help="Max distinct solution families to report with --all. Default: 10")
    parser.add_argument("--test", action="store_true", help="Run the regression corpus (spec section 8)")

    args = parser.parse_args(argv)

    if args.test:
        import tests_corpus
        ok = tests_corpus.run_all()
        return 0 if ok else 1

    if not args.level:
        parser.error("a level file is required (or use --test)")

    try:
        bound = parse_bound(args.bound)
    except ValueError:
        print(f"Error: could not parse --bound '{args.bound}' (expected N or 'lo,hi')", file=sys.stderr)
        return 3

    if sum([args.solve, args.all, args.minimality]) > 1:
        parser.error("--solve, --all, and --minimality are mutually exclusive")

    try:
        level = load_level(args.level)
    except FileNotFoundError:
        print(f"Error: level file not found: {args.level}", file=sys.stderr)
        return 3
    except (ValueError, KeyError) as e:
        print(f"Error: invalid level file: {e}", file=sys.stderr)
        return 3
    except Exception as e:
        print(f"Error: could not read level file: {e}", file=sys.stderr)
        return 3

    if args.solve:
        text, code = solve_only_report(level, bound, args.max_latches)
    elif args.all:
        text, code = all_report(level, bound, args.max_latches, max_families=args.max_families)
    elif args.minimality:
        text, code = minimality_only_report(level, bound, args.max_latches)
    else:
        text, code = full_report(level, bound, args.max_latches, find_all=False, max_families=args.max_families)

    print(text)
    return code


if __name__ == "__main__":
    sys.exit(main())
