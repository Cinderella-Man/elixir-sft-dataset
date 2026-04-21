Write me an Elixir module called `JsonlImporter` that reads a JSONL (JSON Lines) file, validates each record against a provided schema, and returns a structured result splitting valid records from errors.

I need these functions in the public API:

- `JsonlImporter.import_file(file_path, schema)` which reads the JSONL file at the given path and validates every line against the schema. It should return `{:ok, valid_records, error_report}` where `valid_records` is a list of maps (field name => decoded value) for records that passed all validations, and `error_report` is a list of `{line_number, field_name, error_message}` tuples describing every validation failure. Line numbers should be 1-based. If the file doesn't exist, return `{:error, :file_not_found}`. If the file is empty (zero bytes), return `{:error, :empty_file}`.

- `JsonlImporter.import_string(jsonl_string, schema)` which does the same thing but accepts the JSONL content as a binary string instead of a file path. This is useful for testing.

The schema should be a list of field definitions, where each field is a map with these keys:
- `:name` (required) — the field key as a string
- `:required` (optional, default `true`) — if true, the field must be present and non-null; for strings, it must also be non-empty/non-whitespace
- `:type` (optional, default `:string`) — one of `:string`, `:integer`, `:float`, `:boolean`, `:list`
- `:format` (optional) — a regex that the string representation of the field value must match. For convenience, also accept the atom `:email` which should use a reasonable email regex pattern.

Validation rules:
- Required fields that are missing from the JSON object, are `null`, or (for strings) are empty/whitespace-only should produce an error `"is required"`.
- Type checks: `:string` must be a JSON string, `:integer` must be a JSON number that is a whole number, `:float` must be a JSON number (integers are also accepted as valid floats), `:boolean` must be a JSON boolean (`true`/`false`), `:list` must be a JSON array. Type errors should read `"must be a valid <type>"`.
- Format checks only apply to string-typed fields and should produce `"does not match expected format"`.
- A single field can have multiple errors — report all of them, not just the first.
- Lines that are not valid JSON should produce a single error `{line_number, "_line", "invalid JSON"}` and be counted as invalid.

Edge cases to handle:
- UTF-8 BOM (`\xEF\xBB\xBF`) at the start of the file — strip it before parsing.
- Blank lines (empty or whitespace-only) should be silently skipped and not counted in line numbering.
- File with no non-blank lines after BOM stripping — return `{:error, :empty_file}`.
- Extra fields in the JSON object that are not in the schema should be silently ignored (not included in valid records).
- Whitespace around string values should be trimmed before validation.

Use the Jason library for JSON parsing (`:jason` hex package). Do not use any other external dependencies. Give me the complete module in a single file.