# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule CsvImporter do
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
