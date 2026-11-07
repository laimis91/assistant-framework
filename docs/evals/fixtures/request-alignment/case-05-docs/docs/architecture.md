# Architecture

csvtidy reads rows with the standard `csv` module, passes each cell through
`tidy_cell`, and writes either a CSV file or PostgreSQL rows.

Features: whitespace trimming, date normalisation (US month-first by default),
encoding detection, PostgreSQL export, streaming for files larger than memory,
and a plug-in hook for custom cell rules.

Planned: Excel input, a web preview and Windows installers.
