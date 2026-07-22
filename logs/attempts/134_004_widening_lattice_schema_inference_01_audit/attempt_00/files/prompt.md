# Schema Inference from CSV — Widening-Lattice Resolution

Write me an Elixir module called `LatticeSchema` that reads CSV data and infers each column's type by **joining its cell categories in a type-widening lattice** rather than the base task's ad-hoc "same-or-string" rule. Use only the OTP standard library — no external dependencies — and give me the complete module in a single file.

## Public API

- `LatticeSchema.infer_string(csv, opts \\ [])` — takes the CSV content as a string and returns the inferred schema.
- `LatticeSchema.infer_file(path, opts \\ [])` — reads the file at `path` and returns the inferred schema (behaves exactly as if the file's contents were passed to `infer_string/2`).

Both return a plain map `%{"column_name" => :inferred_type}` where each type is one of `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`.

### Options

- `:headers` (boolean, default `true`) — when `true`, the first record is the header row supplying column names; when `false`, all records are data and columns are named `"column_1"`, `"column_2"`, … (1-indexed, by field position).
- `:sample_rows` (positive integer, default `100`) — infer from at most the first N data rows.

## CSV parsing rules

RFC-4180 style, identical to the base task: `\n` record separator with a single trailing newline ignored; comma field separator; double-quoted fields may contain commas; doubled quotes (`""`) are a literal quote; track whether each field was quoted. An **unquoted empty field** is null (ignored for inference); a quoted empty field (`""`) is a non-null empty string value.

## Per-cell categories

For each non-null cell, classify exactly as in the base task: quoted fields are always `string`; otherwise `boolean` (`true`/`false`, case-insensitive), `integer` (`^[+-]?\d+$`), `float` (`^[+-]?\d+\.\d+$`), `date` (valid `YYYY-MM-DD` or `MM/DD/YYYY`), `datetime` (valid `YYYY-MM-DDTHH:MM:SS` or `YYYY-MM-DD HH:MM:SS`), else `string`. Values are used verbatim.

## Column type resolution — the lattice join (this is the difference)

Instead of "all-same-or-else-string", resolve each column by folding its distinct non-null categories through a binary **join** in a widening lattice:

- A column with **no** non-null cells → `:string`.
- The join of a category with itself is that category.
- **Numeric widening:** `integer` and `float` join to `:float` (so an integer/float mix is `:float`, exactly like the base task).
- **Temporal widening:** `date` and `datetime` join to `:datetime` — because a date is a less-precise datetime, a column mixing plain dates and datetimes widens to `:datetime` (this is where the lattice differs from the base task, which would return `:string`).
- Any other pair of distinct categories joins to `:string` (the lattice top). For example: `integer`+`datetime` → `:string`, `boolean`+`integer` → `:string`, `date`+`string` → `:string`.

The join must be commutative and associative, so folding the whole set of distinct categories yields a single well-defined type regardless of order. Concretely:

- All integers → `:integer`; add one float → `:float`.
- All dates (even in different date formats) → `:date`.
- All datetimes → `:datetime`.
- A mix of dates and datetimes → `:datetime`.
- A mix of dates and integers → `:string`.
- Null cells never affect the result.