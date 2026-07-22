# Schema Inference from CSV

Write me an Elixir module called `SchemaInference` that reads CSV data and infers the type of each column. Use only the OTP standard library — no external dependencies — and give me the complete module in a single file.

## Public API

I need exactly these two functions:

- `SchemaInference.infer_string(csv, opts \\ [])` — takes the CSV content as a string and returns the inferred schema.
- `SchemaInference.infer_file(path, opts \\ [])` — reads the file at `path` and returns the inferred schema (behaves exactly as if the file's contents were passed to `infer_string/2`).

Both return a plain map of the form `%{"column_name" => :inferred_type}`, where each type is one of the atoms:

`:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`

### Options

- `:headers` (boolean, default `true`) — when `true`, the **first record** is the header row and supplies the column names. When `false`, there is no header row, every record is data, and columns are named `"column_1"`, `"column_2"`, … (1-indexed, by field position).
- `:sample_rows` (positive integer, default `100`) — infer types from at most the **first N data rows** (data rows exclude the header). If there are fewer data rows than N, use all of them.

## CSV parsing rules

Parse CSV in the RFC-4180 style:

- Records are separated by newlines (`\n`). A single trailing newline at the end of the input must be ignored (i.e. it does not create an extra empty record).
- Fields within a record are separated by commas.
- A field may be **quoted** with double quotes (`"`). A quoted field may contain commas, which are literal and do **not** split the field. Inside a quoted field, a doubled quote (`""`) represents a single literal quote character.
- You must track whether each field was quoted in the source — this affects type inference (see below).

## Null / empty detection

- An **unquoted empty field** (zero-length, e.g. the value between the comma and the newline in `1,`) is treated as **null**. Null cells are ignored when inferring a column's type.
- A quoted empty field (`""`) is a non-null empty **string** value.

## Per-cell type detection

For each **non-null** cell, classify it into exactly one category. **If a field was quoted in the source, its category is always `string`, regardless of its contents** (so a column of quoted numbers infers to `:string`). For unquoted fields, use these rules (the shapes are mutually exclusive, so order does not matter):

- **boolean** — the value is `true` or `false`, matched case-insensitively (`TRUE`, `False`, etc.).
- **integer** — the value matches `^[+-]?\d+$` (an optional sign followed by one or more digits).
- **float** — the value matches `^[+-]?\d+\.\d+$` (an optional sign, digits, a decimal point, then digits). Note `2.0` is a float, not an integer.
- **date** — the value is a **valid calendar date** in one of these formats:
  - `YYYY-MM-DD`
  - `MM/DD/YYYY`
- **datetime** — the value is a **valid** date-and-time in one of these formats:
  - `YYYY-MM-DDTHH:MM:SS`
  - `YYYY-MM-DD HH:MM:SS`
- **string** — anything else (including any value that "looks like" a date but is not a real calendar date, e.g. `13/45/2020`).

## Column type resolution

For each column, look at the categories of all its non-null cells and resolve a single column type:

1. If the column has **no non-null cells** (all null, or no data rows at all) → `:string`.
2. If every non-null cell has the **same** category `c` → `c`.
3. Otherwise, if the set of categories is a subset of `{integer, float}` (i.e. a mix of integers and floats) → `:float`.
4. Otherwise → `:string`.

Some consequences to get right:

- A column of all integers → `:integer`; add a single float and it becomes `:float`.
- A column mixing genuinely different categories (e.g. a date and a datetime, or an integer and a word) → `:string`.
- A column whose dates appear in **different date formats** (some `YYYY-MM-DD`, some `MM/DD/YYYY`) is still `:date`, because every cell's category is `date`.
- Null cells never change the outcome — a column of `[1, null, 2]` is `:integer`.

Field values are used verbatim for detection (no whitespace trimming).