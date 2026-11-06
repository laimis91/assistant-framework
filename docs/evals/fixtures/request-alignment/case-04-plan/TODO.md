# Ideas (not scheduled)

- Replace `notes.json` with SQLite. JSON is fine for current note counts, but a
  database would give us indexes, full-text search and concurrent writers. This
  would be a large rewrite of `notes/store.py` and a one-way data migration.
- `notes find` is a linear scan with a lowercase copy of every note per query.
  It is slow above about 50,000 notes; no user has reported this yet.
- Consider colour output for `notes list`.
