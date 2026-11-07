# Size and language inventory

Use this recipe when the user asks for size or language counts, or when an
unfamiliar repository is large enough that counts help choose where to look.

1. Enumerate tracked files with `git ls-files`, so ignored files stay out.
2. Exclude dependency, build, vendored and generated directories explicitly
   (for example `node_modules/`, `dist/`, `build/`, `vendor/`, generated
   clients), even when they are tracked. Name each exclusion in the report.
3. Prefer a code counter already on PATH, such as `scc`, `tokei` or `cloc`,
   pointed at the same file list. Install nothing; use only tools already
   present, and ask before any installation. Without a counter, group the
   `git ls-files` output by extension and count files and lines.
4. Report Markdown, prompt and other instruction files separately from code.
5. Report what was counted, what was excluded and which tool produced it.

The counts are orientation facts, not quality: size, language mix or line
counts never judge a codebase. A sampled or partial count is reported as such;
never claim full coverage from a sample.
