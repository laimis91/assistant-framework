# csvtidy

`csvtidy` normalises messy CSV files: it trims whitespace, unifies date formats
and can export the cleaned rows to PostgreSQL.

## Usage

```
csvtidy clean input.csv -o output.csv
csvtidy export input.csv --dsn postgresql://localhost/tidy
```

## Running tests

Run `pytest`. Tested on macOS and Linux.

## Licence

MIT
