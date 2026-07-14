Implement the private `process_parsed/2` function. It receives a `{headers, rows}`
tuple (as produced by `parse_csv/1`) and the `schema`, and turns the parsed CSV into
the final `{:ok, valid_rows, error_report}` result.

Behaviour:

- If there are no data rows (the tuple is `{_headers, []}`), return `{:ok, [], []}`
  immediately — no valid rows and no errors.
- Otherwise, validate every data row:
  - Compute the header count and build a `schema_by_name` lookup map from the schema
    (keyed by each field's `:name`).
  - Walk the rows with a 1-based index (data rows only; the header is not counted),
    accumulating a `{valid_rows, error_report}` pair.
  - For each raw row, build a `%{header => trimmed_value}` map with `build_row_map/3`
    and collect its validation errors with `validate_row/3`.
  - If the row has no errors, keep only the schema fields whose `:name` appears in the
    CSV headers, mapping each to its value from the row map (defaulting to `""`), and
    prepend that map to the valid-rows accumulator.
  - If the row has errors, tag each `{field_name, message}` with the row number to
    produce `{row_number, field_name, message}` tuples and append them to the error
    report (so the report stays in row/field order).
- Return `{:ok, valid_rows, error_report}` with the valid rows in their original
  (top-to-bottom) order.

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

  defp process_parsed({_headers, []} = _parsed, _schema) do
    # TODO
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