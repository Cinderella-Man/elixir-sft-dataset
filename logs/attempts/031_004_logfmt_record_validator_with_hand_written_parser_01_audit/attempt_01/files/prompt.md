Write me an Elixir module called `LogfmtValidator` that reads a logfmt-formatted file (one record per line as `key=value` pairs), validates each record against a provided schema, and returns a structured result splitting valid records from errors.

Logfmt is a structured logging format where each line contains space-separated `key=value` pairs. Values containing spaces must be double-quoted. Example:
```
level=info host=web01 method=GET path=/api/users duration=42 success=true
level=error host=web02 method=POST path="/api/data import" duration=abc success=false
```

I need these functions in the public API:

- `LogfmtValidator.validate_file(file_path, schema)` which reads the logfmt file at the given path and validates every line against the schema. It should return `{:ok, valid_records, error_report}` where `valid_records` is a list of maps (field name => string value) for records that passed all validations, and `error_report` is a list of `{line_number, field_name, error_message}` tuples describing every validation failure. Line numbers are 1-based. If the file doesn't exist, return `{:error, :file_not_found}`. If the file is empty (zero bytes), return `{:error, :empty_file}`.

- `LogfmtValidator.validate_string(logfmt_string, schema)` which does the same thing but accepts the logfmt content as a binary string instead of a file path.

The schema should be a list of field definitions, where each field is a map with these keys:
- `:name` (required) — the key name as a string
- `:required` (optional, default `true`) — if true, the key must be present and have a non-empty value
- `:type` (optional, default `:string`) — one of `:string`, `:integer`, `:float`, `:boolean`
- `:format` (optional) — a regex that the field value must match. For convenience, also accept the atom `:ipv4` which should match a standard IPv4 address pattern.

Logfmt parsing rules:
- Each line is one record; keys and values are separated by `=`.
- Unquoted values end at the next space. Quoted values (double quotes) can contain spaces and escaped quotes (`\"`).
- Keys without a `=` sign are treated as boolean flags with value `"true"` (e.g., `verbose` means `verbose=true`).
- Keys with `=` but an empty right side (e.g., `msg=`) have an empty string value.
- Blank lines (empty or whitespace-only) should be silently skipped and not counted in line numbering.
- If a line cannot be parsed at all (e.g., contains an unterminated quote), produce a single error `{line_number, "_line", "malformed logfmt line"}` and count it as invalid.

Validation rules:
- Required fields that are missing or have an empty value should produce an error `"is required"`.
- Type checks: `:integer` values must be parseable by `String.to_integer/1`, `:float` by `String.to_float/1` (also accept integer-formatted strings like `"42"` as valid floats), `:boolean` must be one of `"true"`, `"false"`, `"1"`, `"0"` (case-insensitive). Type errors should read `"must be a valid <type>"`.
- Format checks should produce `"does not match expected format"`.
- A single field can have multiple errors — report all of them, not just the first.
- Extra keys in the record that are not in the schema should be silently ignored (not included in valid records).

Edge cases to handle:
- UTF-8 BOM (`\xEF\xBB\xBF`) at the start of the file — strip it before parsing.
- File with no non-blank lines — return `{:error, :empty_file}`.
- Whitespace around key names and values should be trimmed.
- Duplicate keys on a single line — last occurrence wins.

Do not use any external dependencies (no hex packages). Implement the logfmt parser from scratch. Give me the complete module in a single file.