Implement the private `coerce_type/3` function.

`coerce_type(value, type, field)` performs type coercion on an already-trimmed,
non-empty string `value` according to the declared `type` atom, using `field`
(the schema field definition map) for the field name and any extra options. It
returns a `{errors, coerced_value}` tuple, where `errors` is a list of
`{field_name, error_message}` tuples and `coerced_value` is only meaningful when
`errors` is the empty list `[]`. On any coercion failure, return the error list
together with `nil` as the coerced value.

Handle each supported type as its own function clause:

- `:string` — keep `value` as-is (it is already trimmed). Always succeeds:
  return `{[], value}`.
- `:integer` — parse with `Integer.parse/1`; only accept a clean parse that
  consumes the entire string (`{int, ""}`). On failure the message is
  `"must be a valid integer"`.
- `:float` — accept a proper float string via `Float.parse/1` (consuming the
  whole string), and also accept an integer-formatted string like `"42"` by
  coercing it to a float (`42.0`). On failure the message is
  `"must be a valid float"`.
- `:boolean` — lowercase `value`; anything in `@true_values` coerces to `true`,
  anything in `@false_values` coerces to `false`. Otherwise the message is
  `"must be a valid boolean"`.
- `:date` — parse with `Date.from_iso8601/1`; on `{:ok, date}` return the
  `Date` struct, on `{:error, _}` the message is `"must be a valid date"`.
- `:enum` — fetch the allowed list from the field via `Map.fetch!(field, :values)`;
  if `value` is a member, return it unchanged, otherwise the message is
  `"must be one of: "` followed by the allowed values joined with `", "`.

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
  # CSV parsing configuration
  #
  # Parsing is implemented in a small, self-contained parser below so the module
  # has no external compile-time dependencies. It supports a comma separator and
  # double-quote (`"`) escaping (`""` for a literal quote inside a quoted field).
  # ---------------------------------------------------------------------------

  # Accepted boolean literals (lowercased for comparison).
  @true_values ~w(true 1)
  @false_values ~w(false 0)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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
    case parse_rows(text) do
      [] ->
        {[], []}

      [headers | rows] ->
        trimmed_headers = Enum.map(headers, &String.trim/1)
        {trimmed_headers, rows}
    end
  end

  # Minimal RFC-4180-style CSV parser (comma separator, double-quote escaping).
  # Returns a list of rows, each a list of field strings.
  defp parse_rows(text), do: parse_rows(text, "", [], [], false)

  # End of input: flush the pending field/row unless it is a trailing empty line.
  defp parse_rows(<<>>, field, row, rows, _in_quotes) do
    if field == "" and row == [] do
      Enum.reverse(rows)
    else
      Enum.reverse([Enum.reverse([field | row]) | rows])
    end
  end

  # Escaped quote ("") while inside a quoted field.
  defp parse_rows(<<?", ?", rest::binary>>, field, row, rows, true) do
    parse_rows(rest, field <> "\"", row, rows, true)
  end

  # Opening quote (outside quotes).
  defp parse_rows(<<?", rest::binary>>, field, row, rows, false) do
    parse_rows(rest, field, row, rows, true)
  end

  # Closing quote (inside quotes).
  defp parse_rows(<<?", rest::binary>>, field, row, rows, true) do
    parse_rows(rest, field, row, rows, false)
  end

  # Field separator (outside quotes).
  defp parse_rows(<<?,, rest::binary>>, field, row, rows, false) do
    parse_rows(rest, "", [field | row], rows, false)
  end

  # Row separators (outside quotes).
  defp parse_rows(<<?\r, ?\n, rest::binary>>, field, row, rows, false) do
    parse_rows(rest, "", [], [Enum.reverse([field | row]) | rows], false)
  end

  defp parse_rows(<<?\n, rest::binary>>, field, row, rows, false) do
    parse_rows(rest, "", [], [Enum.reverse([field | row]) | rows], false)
  end

  defp parse_rows(<<?\r, rest::binary>>, field, row, rows, false) do
    parse_rows(rest, "", [], [Enum.reverse([field | row]) | rows], false)
  end

  # Any other byte is appended to the current field verbatim.
  defp parse_rows(<<c, rest::binary>>, field, row, rows, in_quotes) do
    parse_rows(rest, field <> <<c>>, row, rows, in_quotes)
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

  # TODO

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