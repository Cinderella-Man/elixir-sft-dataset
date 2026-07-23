# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `load_file`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

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

## The module with `load_file` missing

```elixir
defmodule CsvLoader do
  @moduledoc """
  Reads CSV data (from a file or string), validates each row against a provided
  schema, coerces values to their declared Elixir types, and returns structured
  results splitting valid rows from errors.

  ## Schema

  A schema is a list of field definition maps:

      [
        %{name: "email", type: :string, format: ~r/@/},
        %{name: "age",   type: :integer},
        %{name: "score", type: :float, required: false, default: 0.0},
        %{name: "active", type: :boolean},
        %{name: "joined", type: :date},
        %{name: "role", type: :enum, values: ["admin", "user", "guest"]}
      ]

  Valid rows are returned as maps with atom keys and typed Elixir values.
  """

  # ---------------------------------------------------------------------------
  # CSV parser definition (NimbleCSV)
  # ---------------------------------------------------------------------------
  NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\"")

  # Accepted boolean literals (lowercased for comparison).
  @true_values ~w(true 1)
  @false_values ~w(false 0)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def load_file(file_path, schema) do
    # TODO
  end

  @spec load_string(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :empty_file}
  def load_string(csv_string, schema) do
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

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(other), do: other

  defp parse_csv(text) do
    case CsvLoader.Parser.parse_string(text, skip_headers: false) do
      [] ->
        {[], []}

      [headers | rows] ->
        trimmed_headers = Enum.map(headers, &String.trim/1)
        {trimmed_headers, rows}
    end
  end

  defp process_parsed({_headers, []}, _schema), do: {:ok, [], []}

  defp process_parsed({headers, rows}, schema) do
    header_count = length(headers)

    {valid_rows, error_report} =
      rows
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {raw_row, row_num}, {valid_acc, err_acc} ->
        row_map = build_row_map(headers, raw_row, header_count)
        {errors, coerced} = validate_and_coerce_row(row_map, schema, headers)

        case errors do
          [] ->
            {[coerced | valid_acc], err_acc}

          _ ->
            tagged = Enum.map(errors, fn {field, msg} -> {row_num, field, msg} end)
            {valid_acc, err_acc ++ tagged}
        end
      end)

    {:ok, Enum.reverse(valid_rows), error_report}
  end

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

  # Validate and coerce a single row.
  # Returns {errors, coerced_map}.
  # coerced_map is only meaningful when errors is empty.
  defp validate_and_coerce_row(row_map, schema, headers) do
    schema
    |> Enum.filter(fn field -> field.name in headers end)
    |> Enum.reduce({[], %{}}, fn field, {errs, coerced} ->
      value = Map.get(row_map, field.name, "")
      key = Map.get(field, :key, String.to_atom(field.name))

      case validate_and_coerce_field(value, field) do
        {:ok, coerced_value} ->
          {errs, Map.put(coerced, key, coerced_value)}

        {:errors, field_errors} ->
          {errs ++ field_errors, coerced}
      end
    end)
  end

  defp validate_and_coerce_field(value, field) do
    required? = Map.get(field, :required, true)
    type = Map.get(field, :type, :string)
    format = Map.get(field, :format, nil)
    default = Map.get(field, :default, nil)
    empty? = value == ""

    # --- Required check ---
    required_errors =
      if required? and empty? do
        [{field.name, "is required"}]
      else
        []
      end

    # --- Handle empty non-required fields ---
    if empty? and not required? do
      if required_errors == [] do
        {:ok, default}
      else
        {:errors, required_errors}
      end
    else
      if empty? and required? do
        # Required and empty — report error, skip type/format
        {:errors, required_errors}
      else
        # Non-empty value: validate format, then type-coerce
        format_errors =
          if format != nil do
            check_format(value, format, field.name)
          else
            []
          end

        {type_errors, coerced_value} = coerce_type(value, type, field)

        all_errors = required_errors ++ format_errors ++ type_errors

        if all_errors == [] do
          {:ok, coerced_value}
        else
          {:errors, all_errors}
        end
      end
    end
  end

  # Type coercion — returns {errors, coerced_value}.
  # coerced_value is only meaningful when errors is [].

  defp coerce_type(value, :string, _field), do: {[], value}

  defp coerce_type(value, :integer, field) do
    case Integer.parse(value) do
      {int, ""} -> {[], int}
      _ -> {[{field.name, "must be a valid integer"}], nil}
    end
  end

  defp coerce_type(value, :float, field) do
    cond do
      match?({_f, ""}, Float.parse(value)) ->
        {f, ""} = Float.parse(value)
        {[], f}

      match?({_i, ""}, Integer.parse(value)) ->
        {i, ""} = Integer.parse(value)
        {[], i * 1.0}

      true ->
        {[{field.name, "must be a valid float"}], nil}
    end
  end

  defp coerce_type(value, :boolean, field) do
    lower = String.downcase(value)

    cond do
      lower in @true_values -> {[], true}
      lower in @false_values -> {[], false}
      true -> {[{field.name, "must be a valid boolean"}], nil}
    end
  end

  defp coerce_type(value, :date, field) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {[], date}
      {:error, _} -> {[{field.name, "must be a valid date"}], nil}
    end
  end

  defp coerce_type(value, :enum, field) do
    allowed = Map.fetch!(field, :values)

    if value in allowed do
      {[], value}
    else
      msg = "must be one of: #{Enum.join(allowed, ", ")}"
      {[{field.name, msg}], nil}
    end
  end

  # Format checker ------------------------------------------------------

  defp check_format(value, %Regex{} = regex, name) do
    if Regex.match?(regex, value) do
      []
    else
      [{name, "does not match expected format"}]
    end
  end
end
```

Output only `load_file` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
