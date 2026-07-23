# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

    {valid_rows, error_report} =
      rows
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {raw_row, row_num}, {valid_acc, err_acc} ->
        row_map = build_row_map(headers, raw_row, header_count)
        errors = validate_row(row_map, schema)

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
  defp validate_row(row_map, schema) do
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

Hey, could you write me an Elixir module called `CsvLoader`? What I need it to do is read a CSV file, validate each row against a schema I hand it, coerce the values into their declared Elixir types, and give me back a structured result that separates the valid rows from the errors.

For the public API, I need two functions. First there's `CsvLoader.load_file(file_path, schema)`, which reads the CSV file at the path I give it and validates and coerces every data row against the schema. I want it to return `{:ok, valid_rows, error_report}`, where `valid_rows` is a list of maps whose keys are the field names as atoms and whose values are properly typed Elixir values — not raw strings — and where `error_report` is a list of `{row_number, field_name, error_message}` tuples describing every validation failure. The valid rows need to come back in the same order they appear in the CSV. Row numbers are 1-based and count only data rows — don't count the header row. If the file doesn't exist, return `{:error, :file_not_found}`, and if the file is empty (zero bytes), return `{:error, :empty_file}`.

Then I need `CsvLoader.load_string(csv_string, schema)`, which does exactly the same thing but takes the CSV content as a binary string instead of a file path — handy for testing. If that content is empty after stripping any BOM (i.e. it trims to an empty string), return `{:error, :empty_file}`.

The schema itself should be a list of field definitions, and each field is a map with these keys: `:name` (required) is the column header name as a string; `:key` (optional) is the atom to use as the map key in the result, and it defaults to the `:name` string converted to an atom via `String.to_atom/1`; `:required` (optional, default `true`) means that when it's true the field has to be present and non-empty; `:type` (optional, default `:string`) is one of `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:enum`; `:values` (required when the type is `:enum`) is a list of allowed string values; `:default` (optional) is a default value to use when the field is empty and not required, and it must already be the correct Elixir type; and `:format` (optional) is a regex that the raw string field value has to match before type coercion.

On the type coercion — this all happens after validation passes. For `:string`, keep the value as a trimmed string. For `:integer`, parse via `String.to_integer/1`, and on failure the error message is `"must be a valid integer"`. For `:float`, parse via `String.to_float/1`, but also accept integer-formatted strings like `"42"` (coerce that to `42.0`); the error message is `"must be a valid float"`. For `:boolean`, `"true"` and `"1"` (case-insensitive) coerce to `true`, and `"false"` and `"0"` coerce to `false`, while anything else gives `"must be a valid boolean"`. For `:date`, it must be ISO 8601 format (`YYYY-MM-DD`) and parseable by `Date.from_iso8601/1`, with the error message `"must be a valid date"`. For `:enum`, the trimmed value must be one of the strings in the `:values` list, case-sensitive, and the error message is `"must be one of: <comma-separated values>"`.

For the validation rules: only process schema fields whose `:name` matches a column in the header row — a schema field whose name doesn't appear in the header gets skipped entirely, so it's neither validated nor included in the result maps, and its key never appears even if it defines a `:default`. Required fields that are empty or whitespace-only should produce an error `"is required"`. Type coercion errors produce the messages I listed above. Format checks produce `"does not match expected format"` and are evaluated before type coercion. A single field can have multiple errors, so report all of them, not just the first. If a row has more columns than the header, silently ignore the extras; if a row has fewer columns than the header, treat the missing ones as empty strings. When a non-required field is empty, use the `:default` value if one is provided, otherwise use `nil`.

There are a few edge cases I want handled too. Strip a UTF-8 BOM (`\xEF\xBB\xBF`) at the start of the file before parsing. A file with only a header row and no data rows should return `{:ok, [], []}`. Handle completely empty fields (adjacent commas) as well as fields wrapped in double quotes that contain commas or newlines inside them. And trim whitespace around field values before validation and coercion.

For parsing, use the NimbleCSV library (the `:nimble_csv` hex package), and please don't pull in any other external dependencies. Give me the complete module in a single file.
