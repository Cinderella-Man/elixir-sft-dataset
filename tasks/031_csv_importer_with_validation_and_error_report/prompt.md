Write me an Elixir module called `CsvImporter` that reads a CSV file, validates each row against a provided schema, and returns a structured result splitting valid rows from errors.

I need these functions in the public API:

- `CsvImporter.import_file(file_path, schema)` which reads the CSV file at the given path and validates every data row against the schema. It should return `{:ok, valid_rows, error_report}` where `valid_rows` is a list of maps (field name => string value) for rows that passed all validations, and `error_report` is a list of `{row_number, field_name, error_message}` tuples describing every validation failure. Row numbers should be 1-based counting only data rows (the header row is row 0 / not counted). If the file doesn't exist, return `{:error, :file_not_found}`. If the file is empty (zero bytes), return `{:error, :empty_file}`.

- `CsvImporter.import_string(csv_string, schema)` which does the same thing but accepts the CSV content as a binary string instead of a file path. This is useful for testing.

The schema should be a list of field definitions, where each field is a map with these keys:
- `:name` (required) — the column header name as a string
- `:required` (optional, default `true`) — if true, the field must be present and non-empty
- `:type` (optional, default `:string`) — one of `:string`, `:integer`, `:float`, `:boolean`
- `:format` (optional) — a regex that the field value must match. For convenience, also accept the atom `:email` which should use a reasonable email regex pattern.

Validation rules:
- Required fields that are empty or whitespace-only should produce an error `"is required"`.
- Type checks: `:integer` values must be parseable by `String.to_integer/1`, `:float` by `String.to_float/1` (also accept integer-formatted strings like `"42"` as valid floats), `:boolean` must be one of `"true"`, `"false"`, `"1"`, `"0"` (case-insensitive). Type errors should read `"must be a valid <type>"`.
- Format checks should produce `"does not match expected format"`.
- A single field can have multiple errors — report all of them, not just the first.
- If a row has more columns than the header, ignore the extras silently. If a row has fewer columns than the header, treat the missing columns as empty strings.

Edge cases to handle:
- UTF-8 BOM (`\xEF\xBB\xBF`) at the start of the file — strip it before parsing.
- File with only a header row and no data rows — return `{:ok, [], []}`.
- Completely empty fields (adjacent commas) and fields wrapped in double quotes with commas or newlines inside them.
- Whitespace around field values should be trimmed.

Use the NimbleCSV library for parsing (`:nimble_csv` hex package). Do not use any other external dependencies. Give me the complete module in a single file.