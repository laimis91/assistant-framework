"""Command-line entry point."""
import argparse
import csv

from csvtidy.tidy import tidy_cell


def _read_rows(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return [[tidy_cell(cell) for cell in row] for row in csv.reader(handle)]


def main(argv=None):
    parser = argparse.ArgumentParser(prog="csvtidy")
    sub = parser.add_subparsers(dest="command", required=True)
    clean = sub.add_parser("clean")
    clean.add_argument("input")
    clean.add_argument("-o", "--output", required=True)
    export = sub.add_parser("export")
    export.add_argument("input")
    export.add_argument("--dsn", required=True)
    args = parser.parse_args(argv)

    rows = _read_rows(args.input)
    if args.command == "clean":
        with open(args.output, "w", newline="", encoding="utf-8") as handle:
            csv.writer(handle).writerows(rows)
    else:
        from csvtidy.export import export_rows

        print(export_rows(rows, args.dsn))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
