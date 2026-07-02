# Schema Inference from CSV — Nullable & Unique Column Profiler

Write me an Elixir module called `SchemaProfiler` that reads CSV data and, for each column, infers not just a type but a small **profile**: its inferred type, whether the column is nullable, and whether its values are unique. Use only the OTP standard library — no external dependencies — and give me the complete module in a single file.

## Public API

I need exactly these two functions:

- `SchemaProfiler.infer_string(csv, opts \\ [])` — takes the CSV content as a string and returns the inferred schema.
- `SchemaProfiler.infer_file(path, opts \\ [])` — reads the file at `path` and returns the inferred schema (behaves exactly as if the file's contents were passed to `infer_string/2`).

Both return a plain map of the form `%{"column_name" => %{type: t, nullable: n, unique: u}}` where:

- `type` is one of the atoms `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`.
- `nullable` is a boolean.
- `unique` is a boolean.

### Options

- `:headers` (boolean, default `true`) — when `true`, the **first record** is the header row and supplies the column names. When `false`, there is no header row, every record is data, and columns are named `"column_1"`, `"column_2"`, … (1-indexed, by field position).
- `:sample_rows` (positive integer, default `100`) — infer from at most the **first N data rows** (data rows exclude the header). If there are fewer data rows than N, use all of them.

## CSV parsing rules

Parse CSV in the RFC-4180 style:

- Records are separated by newlines (`\n`). A single trailing newline at the end of the input must be ignored (it does not create an extra empty record).
- Fields within a record are separated by commas.
- A field may be **quoted** with double quotes (`"`). A quoted field may contain commas (literal, no split). Inside a quoted field, a doubled quote (`""`) represents a single literal quote character.
- Track whether each field was quoted — this affects type inference.

## Null / empty detection

- An **unquoted empty field** (zero-length) is treated as **null**.
- A quoted empty field (`""`) is a non-null empty **string** value.
- A cell that is **missing** because a data row is shorter than the column's field position is also treated as **null** for that column.

## Per-cell type detection (same as the base task)

For each **non-null** cell, classify it into exactly one category. **If a field was quoted in the source, its category is always `string`.** For unquoted fields:

- **boolean** — `true` or `false`, case-insensitive.
- **integer** — matches `^[+-]?\d+$`.
- **float** — matches `^[+-]?\d+\.\d+$` (so `2.0` is a float).
- **date** — a valid calendar date in `YYYY-MM-DD` or `MM/DD/YYYY`.
- **datetime** — a valid date-and-time in `YYYY-MM-DDTHH:MM:SS` or `YYYY-MM-DD HH:MM:SS`.
- **string** — anything else (including values that look like a date but are not real calendar dates).

Values are used verbatim (no whitespace trimming).

## Type resolution (same as the base task)

For each column, over the categories of its **non-null** cells:

1. No non-null cells → `:string`.
2. All the same category `c` → `c`.
3. A mix that is a subset of `{integer, float}` → `:float`.
4. Otherwise → `:string`.

## Nullability

`nullable` is `true` when the column has **at least one null cell** in the sampled data rows — either an unquoted empty field or a missing field (row shorter than the column position). Otherwise `false`. A header-only file (no data rows) yields `nullable: false` for every column.

## Uniqueness

`unique` is `true` when the column's **non-null values are all distinct**, comparing the verbatim field string values (ignoring the quoted flag). A column with zero or one non-null value is trivially `unique: true`. Null cells never count toward uniqueness.