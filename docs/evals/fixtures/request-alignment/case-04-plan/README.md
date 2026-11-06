# notes

A small command-line notes tool. Each user's notes live in a single
`notes.json` file in their data directory (`~/.notes/notes.json` by default).
The tool is installed on users' own machines, and users upgrade and downgrade
releases themselves with `pip install notes==<version>`.

## Commands

- `notes add <text>` — add a note
- `notes list` — list notes
- `notes find <text>` — find notes containing text

## Storage format

`notes.json` is a JSON object with a `version` field and a `notes` array. Each
note has an integer `id` and a `text` string. The current release, 1.4.0,
writes `"version": 1`.

## Development

Run the tests with `python3 -m unittest discover -s tests`.
