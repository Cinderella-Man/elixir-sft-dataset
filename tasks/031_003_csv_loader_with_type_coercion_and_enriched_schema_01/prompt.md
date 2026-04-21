Write me an Elixir module called `CsvLoader` that reads a CSV file, validates each row against a provided schema, coerces values to their declared Elixir types, and returns a structured result splitting valid rows from errors.

I need these functions in the public API:

- `CsvLoader.load_file(file_path, schema)` which reads the CSV file at the given path, validates and coerces every data row against the schema. It should return `{:ok, valid_rows, error_report}` where `valid_rows` is a list of maps with field names as atom keys and properly typed Elixir values (not raw strings), and `error_report` is a list of `{row_number, field_name, error_message}` tuples describing every validation failure. Row numbers should be 1-based counting only data rows (the header row is not counted). If the file doesn't exist, return `{:error, :file_not_found}`. If the file is empty (zero bytes), return `{:error, :empty_file}`.

- `CsvLoader.load_string(csv_string, schema)` which does the same thing but accepts the CSV content as a binary string instead of a file path. This is useful for testing.

The schema should be a list of field definitions, where each field is a map with these keys:
- `:name` (required) — the column header name as a string
- `:key` (optional) — the atom to use as the map key in the result; defaults to the `:name` string converted to an atom via `String.to_atom/1`
- `:required` (optional, default `true`) — if true, the field must be present and non-empty
- `:type` (optional, default `:string`) — one of `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:enum`
- `:values` (required when type is `:enum`) — a list of allowed string values
- `:default` (optional) — a default value to use when the field is empty and not required; must already be the correct Elixir type
- `:format` (optional) — a regex that the raw string field value must match before type coercion

Type coercion rules (applied after validation passes):
- `:string` — value is kept as a trimmed string.
- `:integer` — parsed via `String.to_integer/1`. Error message: `"must be a valid integer"`.
- `:float` — parsed via `String.to_float/1`; also accept integer-formatted strings like `"42"` (coerce to `42.0`). Error message: `"must be a valid float"`.
- `:boolean` — `"true"` and `"1"` (case-insensitive) coerce to `true`, `"false"` and `"0"` to `false`. Anything else: `"must be a valid boolean"`.
- `:date` — must be in ISO 8601 format (`YYYY-MM-DD`) and parseable by `Date.from_iso8601/1`. Error message: `"must be a valid date"`.
- `:enum` — the trimmed value must be one of the strings in the `:values` list (case-sensitive). Error message: `"must be one of: <comma-separated values>"`.

Validation rules:
- Required fields that are empty or whitespace-only should produce an error `"is required"`.
- Type coercion errors produce the messages listed above.
- Format checks should produce `"does not match expected format"` and are evaluated before type coercion.
- A single field can have multiple errors — report all of them, not just the first.
- If a row has more columns than the header, ignore the extras silently. If a row has fewer columns than the header, treat the missing columns as empty strings.
- When a non-required field is empty: if `:default` is provided, use the default value; otherwise use `nil`.

Edge cases to handle:
- UTF-8 BOM (`\xEF\xBB\xBF`) at the start of the file — strip it before parsing.
- File with only a header row and no data rows — return `{:ok, [], []}`.
- Completely empty fields (adjacent commas) and fields wrapped in double quotes with commas or newlines inside them.
- Whitespace around field values should be trimmed before validation and coercion.

Use the NimbleCSV library for parsing (`:nimble_csv` hex package). Do not use any other external dependencies. Give me the complete module in a single file.