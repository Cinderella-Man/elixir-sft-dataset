# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule CsvImporter do
  @moduledoc """
  Reads CSV data (from a file or string), validates each row against a provided
  schema, and returns structured results splitting valid rows from errors.

  ## Schema

  A schema is a list of field definition maps:

      [
        %{name: "email", required: true, type: :string, format: :email},
        %{name: "age",   required: true, type: :integer},
        %{name: "score", required: false, type: :float},
        %{name: "active", type: :boolean}
      ]

  Each field map supports:
    - `:name`     (required) — column header name (string)
    - `:required` (optional, default `true`) — whether the field must be non-empty
    - `:type`     (optional, default `:string`) — `:string | :integer | :float | :boolean`
    - `:format`   (optional) — a `Regex` or the atom `:email`
  """

  # ---------------------------------------------------------------------------
  # CSV parser definition (NimbleCSV)
  # ---------------------------------------------------------------------------
  NimbleCSV.define(CsvImporter.Parser, separator: ",", escape: "\"")

  # A reasonable email regex — intentionally permissive.
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  # Accepted boolean literals (lowercased for comparison).
  @boolean_values ~w(true false 1 0)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Import a CSV file at `file_path`, validate every data row against `schema`.

  Returns:
    - `{:ok, valid_rows, error_report}` on success
    - `{:error, :file_not_found}` if the file does not exist
    - `{:error, :empty_file}` if the file is zero bytes
  """
  @spec import_file(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :file_not_found | :empty_file}
  def import_file(file_path, schema) do
    case File.read(file_path) do
      {:ok, ""} ->
        {:error, :empty_file}

      {:ok, contents} ->
        import_string(contents, schema)

      {:error, :enoent} ->
        {:error, :file_not_found}
    end
  end

  @doc """
  Import CSV content given directly as a binary string.

  Returns `{:ok, valid_rows, error_report}`, or `{:error, :empty_file}` when the
  input is empty or whitespace-only.
  """
  @spec import_string(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :empty_file}
  def import_string(csv_string, schema) do
    stripped = strip_bom(csv_string)

    if String.trim(stripped) == "" do
      {:error, :empty_file}
    else
      stripped
      |> parse_csv()
      |> process_parsed(schema)
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  # Strip a UTF-8 BOM if present.
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(other), do: other

  # Parse the raw CSV text into {headers, rows}.
  # Returns {headers :: [String.t()], rows :: [[String.t()]]}.
  defp parse_csv(text) do
    # NimbleCSV.parse_string/2 raises on completely empty input, so guard.
    lines =
      text
      |> String.trim_trailing()
      |> String.split(~r/\r?\n/, parts: 2)

    case lines do
      [""] ->
        # Only whitespace / effectively empty — but import_string won't
        # receive truly empty strings from import_file (caught earlier).
        {[], []}

      [header_line] ->
        # Header only, no data rows.
        headers = parse_header(header_line)
        {headers, []}

      [_header_line | _rest] ->
        # At least one data row. Use NimbleCSV for proper RFC 4180 parsing.
        [headers | rows] = CsvImporter.Parser.parse_string(text, skip_headers: false)
        trimmed_headers = Enum.map(headers, &String.trim/1)
        {trimmed_headers, rows}
    end
  end

  # Fallback header parser for the single-line case (no data rows).
  defp parse_header(line) do
    [row] = CsvImporter.Parser.parse_string(line <> "\n", skip_headers: false)
    Enum.map(row, &String.trim/1)
  end

  # With parsed headers and rows, run validation.
  defp process_parsed({_headers, []} = _parsed, _schema) do
    {:ok, [], []}
  end

  defp process_parsed({headers, rows}, schema) do
    header_count = length(headers)
    schema_by_name = Map.new(schema, fn field -> {field.name, field} end)

    {valid_rows, error_report} =
      rows
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {raw_row, row_num}, {valid_acc, err_acc} ->
        row_map = build_row_map(headers, raw_row, header_count)
        errors = validate_row(row_map, schema, schema_by_name)

        case errors do
          [] ->
            # Keep only schema fields that are present in the CSV headers.
            filtered =
              schema
              |> Enum.filter(fn field -> field.name in headers end)
              |> Enum.map(fn field -> {field.name, Map.get(row_map, field.name, "")} end)
              |> Map.new()

            {[filtered | valid_acc], err_acc}

          _ ->
            tagged = Enum.map(errors, fn {field, msg} -> {row_num, field, msg} end)
            {valid_acc, err_acc ++ tagged}
        end
      end)

    {:ok, Enum.reverse(valid_rows), error_report}
  end

  # Build a map of %{header_name => trimmed_value} for one row.
  # Extra columns beyond the header count are silently ignored.
  # Missing columns are filled with "".
  defp build_row_map(headers, raw_row, header_count) do
    padded =
      if length(raw_row) < header_count do
        raw_row ++ List.duplicate("", header_count - length(raw_row))
      else
        Enum.take(raw_row, header_count)
      end

    headers
    |> Enum.zip(padded)
    |> Map.new(fn {h, v} -> {h, String.trim(v)} end)
  end

  # Validate a single row map against the full schema.
  # Returns a list of {field_name, error_message} tuples (empty if valid).
  defp validate_row(row_map, schema, _schema_by_name) do
    Enum.flat_map(schema, fn field ->
      value = Map.get(row_map, field.name, "")
      validate_field(value, field)
    end)
  end

  # Validate a single field value against its field definition.
  # Returns a list of {field_name, message} tuples.
  defp validate_field(value, field) do
    required? = Map.get(field, :required, true)
    type = Map.get(field, :type, :string)
    format = Map.get(field, :format, nil)
    empty? = value == ""

    required_errors =
      if required? and empty? do
        [{field.name, "is required"}]
      else
        []
      end

    # Type and format checks only apply to non-empty values.
    type_errors =
      if not empty? do
        check_type(value, type, field.name)
      else
        []
      end

    format_errors =
      if not empty? and format != nil do
        check_format(value, format, field.name)
      else
        []
      end

    required_errors ++ type_errors ++ format_errors
  end

  # Type checkers -------------------------------------------------------

  defp check_type(_value, :string, _name), do: []

  defp check_type(value, :integer, name) do
    case Integer.parse(value) do
      {_int, ""} -> []
      _ -> [{name, "must be a valid integer"}]
    end
  end

  defp check_type(value, :float, name) do
    cond do
      # Try float first ("3.14")
      match?({_f, ""}, Float.parse(value)) -> []
      # Accept plain integers as valid floats ("42")
      match?({_i, ""}, Integer.parse(value)) -> []
      true -> [{name, "must be a valid float"}]
    end
  end

  defp check_type(value, :boolean, name) do
    if String.downcase(value) in @boolean_values do
      []
    else
      [{name, "must be a valid boolean"}]
    end
  end

  # Format checker ------------------------------------------------------

  defp check_format(value, :email, name) do
    check_format(value, @email_regex, name)
  end

  defp check_format(value, %Regex{} = regex, name) do
    if Regex.match?(regex, value) do
      []
    else
      [{name, "does not match expected format"}]
    end
  end
end
```

## New specification

Write me an Elixir module called `CsvLoader` that reads a CSV file, validates each row against a provided schema, coerces values to their declared Elixir types, and returns a structured result splitting valid rows from errors.

I need these functions in the public API:

- `CsvLoader.load_file(file_path, schema)` which reads the CSV file at the given path, validates and coerces every data row against the schema. It should return `{:ok, valid_rows, error_report}` where `valid_rows` is a list of maps with field names as atom keys and properly typed Elixir values (not raw strings), and `error_report` is a list of `{row_number, field_name, error_message}` tuples describing every validation failure. Valid rows appear in the same order they occur in the CSV. Row numbers should be 1-based counting only data rows (the header row is not counted). If the file doesn't exist, return `{:error, :file_not_found}`. If the file is empty (zero bytes), return `{:error, :empty_file}`.

- `CsvLoader.load_string(csv_string, schema)` which does the same thing but accepts the CSV content as a binary string instead of a file path. This is useful for testing. If the content is empty (after stripping any BOM, trims to an empty string), return `{:error, :empty_file}`.

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
- Only schema fields whose `:name` matches a column in the header row are processed. A schema field whose name does not appear in the header is skipped entirely — it is neither validated nor included in the result maps, and its key never appears even if it defines a `:default`.
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
