# Optional pattern library

The pattern-library tool provides opt-in access to local design-pattern
examples. It is metadata-first: indexing and search return identifiers,
relative paths, classification, hashes, and word counts, never source bodies or
configured roots. `show` is the only source-reading command and requires an
explicit library ID and safe relative path.

The default personal or company installation creates no configuration or
index. When the configuration file is absent, every command returns the clean
`not_configured` status without prompting the agent or user. This keeps local
examples optional and prevents a personal library from leaking into a company
installation.

## Configure explicitly

Create a JSON file outside the framework repository. Relative roots are
resolved from that configuration file's directory.

```json
{
  "schema_version": "1.0",
  "libraries": [
    {
      "id": "design-patterns",
      "root": "./design-pattern-examples"
    }
  ]
}
```

The schema intentionally supports only `id` and `root`. Library IDs must contain
letters, numbers, underscores, or hyphens. Roots must be existing directories
and cannot themselves be symlinks.

## Commands

```bash
tools/patterns/pattern-library.sh validate-config --config ./pattern-libraries.json
tools/patterns/pattern-library.sh build-index --config ./pattern-libraries.json --output ./pattern-index.json
tools/patterns/pattern-library.sh search --config ./pattern-libraries.json --query "factory composition"
tools/patterns/pattern-library.sh show --config ./pattern-libraries.json --library design-patterns --relative-path Creational.Factories.Factory.cs.txt
```

Search checks metadata only and returns at most three matches by default. A
caller may request one through five matches with `--limit`; workflow use should
keep the default unless more candidates are necessary. Index entries contain:

- library ID and relative path;
- category, pattern, and variant inferred from dot-separated filenames;
- detected language;
- SHA-256 hash and word count.

Indexing does not follow symlinks. `show` rejects absolute paths, traversal,
backslashes, and symlinks at every requested path component. Inspect a candidate
only after its metadata makes it relevant, and apply it only when the current
code has a concrete design force. Educational examples, including deliberate
counterexamples, are evidence to evaluate rather than templates to copy.
