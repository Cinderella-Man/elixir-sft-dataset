# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

Hey, could you write me an Elixir module called `CsvLoader`? What I need it to do is read a CSV file, validate each row against a schema I hand it, coerce the values into their declared Elixir types, and give me back a structured result that separates the valid rows from the errors.

For the public API, I need two functions. First there's `CsvLoader.load_file(file_path, schema)`, which reads the CSV file at the path I give it and validates and coerces every data row against the schema. I want it to return `{:ok, valid_rows, error_report}`, where `valid_rows` is a list of maps whose keys are the field names as atoms and whose values are properly typed Elixir values — not raw strings — and where `error_report` is a list of `{row_number, field_name, error_message}` tuples describing every validation failure. The valid rows need to come back in the same order they appear in the CSV. Row numbers are 1-based and count only data rows — don't count the header row. If the file doesn't exist, return `{:error, :file_not_found}`, and if the file is empty (zero bytes), return `{:error, :empty_file}`.

Then I need `CsvLoader.load_string(csv_string, schema)`, which does exactly the same thing but takes the CSV content as a binary string instead of a file path — handy for testing. If that content is empty after stripping any BOM (i.e. it trims to an empty string), return `{:error, :empty_file}`.

The schema itself should be a list of field definitions, and each field is a map with these keys: `:name` (required) is the column header name as a string; `:key` (optional) is the atom to use as the map key in the result, and it defaults to the `:name` string converted to an atom via `String.to_atom/1`; `:required` (optional, default `true`) means that when it's true the field has to be present and non-empty; `:type` (optional, default `:string`) is one of `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:enum`; `:values` (required when the type is `:enum`) is a list of allowed string values; `:default` (optional) is a default value to use when the field is empty and not required, and it must already be the correct Elixir type; and `:format` (optional) is a regex that the raw string field value has to match before type coercion.

On the type coercion — this all happens after validation passes. For `:string`, keep the value as a trimmed string. For `:integer`, parse via `String.to_integer/1`, and on failure the error message is `"must be a valid integer"`. For `:float`, parse via `String.to_float/1`, but also accept integer-formatted strings like `"42"` (coerce that to `42.0`); the error message is `"must be a valid float"`. For `:boolean`, `"true"` and `"1"` (case-insensitive) coerce to `true`, and `"false"` and `"0"` coerce to `false`, while anything else gives `"must be a valid boolean"`. For `:date`, it must be ISO 8601 format (`YYYY-MM-DD`) and parseable by `Date.from_iso8601/1`, with the error message `"must be a valid date"`. For `:enum`, the trimmed value must be one of the strings in the `:values` list, case-sensitive, and the error message is `"must be one of: <comma-separated values>"`.

For the validation rules: only process schema fields whose `:name` matches a column in the header row — a schema field whose name doesn't appear in the header gets skipped entirely, so it's neither validated nor included in the result maps, and its key never appears even if it defines a `:default`. Required fields that are empty or whitespace-only should produce an error `"is required"`. Type coercion errors produce the messages I listed above. Format checks produce `"does not match expected format"` and are evaluated before type coercion. A single field can have multiple errors, so report all of them, not just the first. If a row has more columns than the header, silently ignore the extras; if a row has fewer columns than the header, treat the missing ones as empty strings. When a non-required field is empty, use the `:default` value if one is provided, otherwise use `nil`.

There are a few edge cases I want handled too. Strip a UTF-8 BOM (`\xEF\xBB\xBF`) at the start of the file before parsing. A file with only a header row and no data rows should return `{:ok, [], []}`. Handle completely empty fields (adjacent commas) as well as fields wrapped in double quotes that contain commas or newlines inside them. And trim whitespace around field values before validation and coercion.

For parsing, use the NimbleCSV library (the `:nimble_csv` hex package), and please don't pull in any other external dependencies. Give me the complete module in a single file.

## The buggy module

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

  @doc """
  Loads CSV at `file_path`, coercing rows to `schema`.

  Returns `{:ok, valid_rows, error_report}` (the same 3-tuple `load_string/2`
  documents) or `{:error, :file_not_found | :empty_file}`.
  """
  @spec load_file(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :file_not_found | :empty_file}
  def load_file(file_path, schema) do
    case File.read(file_path) do
      {:ok, ""} ->
        {:error, :empty_file}

      {:ok, contents} ->
        load_string(contents, schema)

      {:error, :enoent} ->
        {:error, :file_not_found}
    end
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
        trimmed_headers = Enum.map(headers, &String.trim/2)
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

## Failing test report

```
33 of 36 test(s) failed:

  * test imports a fully valid CSV with correctly typed values
      &String.trim/2 with arity 2 called with 1 argument ("name")

  * test valid rows use atom keys
      &String.trim/2 with arity 2 called with 1 argument ("name")

  * test custom :key option overrides the atom key
      &String.trim/2 with arity 2 called with 1 argument ("Full Name")

  * test integer coercion
      &String.trim/2 with arity 2 called with 1 argument ("name")

  (…29 more)
```
