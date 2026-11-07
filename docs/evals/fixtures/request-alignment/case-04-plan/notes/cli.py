"""Command-line entry point."""
import argparse
import os

from notes import store
from notes.search import find

DEFAULT_PATH = os.path.expanduser("~/.notes/notes.json")


def main(argv=None):
    parser = argparse.ArgumentParser(prog="notes")
    parser.add_argument("--file", default=DEFAULT_PATH)
    sub = parser.add_subparsers(dest="command", required=True)
    add = sub.add_parser("add")
    add.add_argument("text")
    sub.add_parser("list")
    finder = sub.add_parser("find")
    finder.add_argument("text")
    args = parser.parse_args(argv)

    notes = store.load(args.file)
    if args.command == "add":
        next_id = max((note["id"] for note in notes), default=0) + 1
        notes.append({"id": next_id, "text": args.text})
        store.save(args.file, notes)
        print(next_id)
    elif args.command == "list":
        for note in notes:
            print(f"{note['id']}: {note['text']}")
    elif args.command == "find":
        for note in find(notes, args.text):
            print(f"{note['id']}: {note['text']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
