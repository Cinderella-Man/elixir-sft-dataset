Hey — I need you to write me an Elixir module called `JsonlImporter`. The job is to read a JSONL (JSON Lines) file, validate each record against a schema I hand it, and give me back a structured result that separates the records that passed from the ones that failed. Please give me the complete module in a single file.

For the public API, I need two functions. The first is `JsonlImporter.import_file(file_path, schema)`. It reads the JSONL file at the given path and validates every line against the schema. When things go well it should return `{:ok, valid_records, error_report}`, where `valid_records` is a list of maps (field name => decoded value) for the records that passed all validations, kept in the order they appear in the input, and `error_report` is a list of `{line_number, field_name, error_message}` tuples describing every validation failure. Make the line numbers 1-based. If the file doesn't exist, return `{:error, :file_not_found}`. If the file is empty (zero bytes), return `{:error, :empty_file}`.

The second is `JsonlImporter.import_string(jsonl_string, schema)`, which does exactly the same thing but takes the JSONL content as a binary string instead of a file path — handy for testing.

About the schema: it's a list of field definitions, and each field is a map with these keys:
- `:name` (required) — the field key as a string
- `:required` (optional, default `true`) — if true, the field must be present and non-null; for strings, it must also be non-empty/non-whitespace
- `:type` (optional, default `:string`) — one of `:string`, `:integer`, `:float`, `:boolean`, `:list`
- `:format` (optional) — a regex that the string representation of the field value must match. For convenience, also accept the atom `:email`, which should use a reasonable email regex pattern.

Here's how I want the validation to work:
- Required fields that are missing from the JSON object, are `null`, or (for strings) are empty/whitespace-only should produce an error `"is required"`.
- For type checks: `:string` must be a JSON string, `:integer` must be a JSON number that is a whole number, `:float` must be a JSON number (integers are also accepted as valid floats), `:boolean` must be a JSON boolean (`true`/`false`), and `:list` must be a JSON array. Type errors should read `"must be a valid <type>"`.
- Format checks only apply to string-typed fields and should produce `"does not match expected format"`.
- A single field can have multiple errors — I want all of them reported, not just the first.
- Lines that aren't valid JSON — or that parse to a valid JSON value that isn't an object (for example an array like `[1, 2, 3]` or a bare scalar) — should produce a single error `{line_number, "_line", "invalid JSON"}` and be counted as invalid.

A few edge cases I need handled:
- A UTF-8 BOM (`\xEF\xBB\xBF`) at the start of the file — strip it before parsing.
- Blank lines (empty or whitespace-only) should be silently skipped and not counted in line numbering.
- A file with no non-blank lines after BOM stripping — return `{:error, :empty_file}`.
- Extra fields in the JSON object that aren't in the schema should be silently ignored (not included in valid records).
- Whitespace around string values should be trimmed before validation, and the trimmed value is what appears in the returned valid record.

Use the Jason library for JSON parsing (the `:jason` hex package), and please don't pull in any other external dependencies.
