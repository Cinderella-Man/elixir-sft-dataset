Implement the private `process_lines/2` function.

It receives `lines` — a list of non-blank logfmt lines (blank lines have already
been filtered out) — and `schema`, the list of field-definition maps. It must walk
the lines in order, parse and validate each one, and return
`{:ok, valid_records, error_report}` where `valid_records` is the list of maps for
records that passed all validations (in original order) and `error_report` is the
flat list of `{line_number, field_name, error_message}` tuples for every failure.

Details:

- Pair each line with a 1-based line number (the first line is line 1). Since blank
  lines were already removed, numbering is over the surviving lines only.
- Reduce over the numbered lines, accumulating two things: the valid records and the
  error tuples.
- For each line, parse it with `parse_logfmt_line/1`:
  - On `{:ok, record}`, validate it with `validate_record/2`:
    - If validation returns no errors, build the filtered map with
      `build_valid_record/2` and prepend it to the accumulated valid records.
    - Otherwise, tag each `{field, msg}` error with the current line number to form
      `{line_num, field, msg}` tuples and append them to the accumulated errors.
  - On `{:error, :malformed}`, append a single
    `{line_num, "_line", "malformed logfmt line"}` error and treat the line as invalid.
- Because valid records are accumulated by prepending, reverse them before returning
  so the result preserves the original line order. Return
  `{:ok, Enum.reverse(valid_records), error_report}`.

```elixir
defmodule LogfmtValidator do
  @moduledoc """
  Reads logfmt data (from a file or string), validates each record against a
  provided schema, and returns structured results splitting valid records from errors.

  ## Logfmt Format

  Each line contains space-separated `key=value` pairs:

      level=info host=web01 method=GET path=/api/users duration=42

  Values with spaces are double-quoted:

      msg="hello world" path="/api/data import"

  Keys without `=` are boolean flags (value is "true"):

      verbose debug level=info

  ## Schema

  A schema is a list of field definition maps:

      [
        %{name: "level", required: true, type: :string},
        %{name: "duration", required: true, type: :integer},
        %{name: "host", format: ~r/^web\d+$/},
        %{name: "ip", format: :ipv4, required: false}
      ]
  """

  # A reasonable IPv4 regex.
  @ipv4_regex ~r/^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$/

  # Accepted boolean literals (lowercased for comparison).
  @boolean_values ~w(true false 1 0)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec validate_file(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :file_not_found | :empty_file}
  def validate_file(file_path, schema) do
    case File.read(file_path) do
      {:ok, ""} ->
        {:error, :empty_file}

      {:ok, contents} ->
        validate_string(contents, schema)

      {:error, :enoent} ->
        {:error, :file_not_found}
    end
  end

  @spec validate_string(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :empty_file}
  def validate_string(logfmt_string, schema) do
    stripped = strip_bom(logfmt_string)

    lines =
      stripped
      |> String.split(~r/\r?\n/)
      |> Enum.reject(fn line -> String.trim(line) == "" end)

    if lines == [] do
      {:error, :empty_file}
    else
      process_lines(lines, schema)
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(other), do: other

  defp process_lines(lines, schema) do
    # TODO
  end

  # Build a map containing only the fields specified in the schema.
  defp build_valid_record(record, schema) do
    schema
    |> Enum.map(fn field ->
      {field.name, Map.get(record, field.name, "")}
    end)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Logfmt parser
  # ---------------------------------------------------------------------------

  @doc false
  def parse_logfmt_line(line) do
    trimmed = String.trim(line)

    case do_parse(trimmed, %{}) do
      {:ok, pairs} -> {:ok, pairs}
      :error -> {:error, :malformed}
    end
  end

  # Recursive logfmt parser.
  # Parses space-separated key=value pairs or bare keys (boolean flags).
  defp do_parse("", acc), do: {:ok, acc}

  defp do_parse(input, acc) do
    input = String.trim_leading(input)

    if input == "" do
      {:ok, acc}
    else
      case parse_key(input) do
        {:ok, key, rest} ->
          rest = String.trim_leading(rest)

          case rest do
            "=" <> after_eq ->
              # Do NOT trim_leading on after_eq here.
              # If `after_eq` starts with a space, it indicates the value for this key is empty.
              case parse_value(after_eq) do
                {:ok, value, remaining} ->
                  do_parse(remaining, Map.put(acc, String.trim(key), String.trim(value)))

                :error ->
                  :error
              end

            _ ->
              # Bare key — boolean flag, value is "true"
              do_parse(rest, Map.put(acc, String.trim(key), "true"))
          end

        :error ->
          :error
      end
    end
  end

  # Parse a key: sequence of non-space, non-= characters.
  defp parse_key(input) do
    case Regex.run(~r/^([^\s=]+)(.*)$/s, input) do
      [_, key, rest] -> {:ok, key, rest}
      _ -> :error
    end
  end

  # Parse a value: either a quoted string or an unquoted token.
  defp parse_value("\"" <> rest) do
    parse_quoted_value(rest, "")
  end

  defp parse_value("") do
    # key= with empty value
    {:ok, "", ""}
  end

  defp parse_value(input) do
    # Unquoted value: everything until the next space.
    case String.split(input, ~r/\s/, parts: 2) do
      [value] -> {:ok, value, ""}
      [value, remaining] -> {:ok, value, remaining}
    end
  end

  # Parse inside a quoted value, handling escaped quotes.
  defp parse_quoted_value("", _acc), do: :error  # Unterminated quote

  defp parse_quoted_value("\\\"" <> rest, acc) do
    parse_quoted_value(rest, acc <> "\"")
  end

  defp parse_quoted_value("\"" <> rest, acc) do
    {:ok, acc, rest}
  end

  defp parse_quoted_value(<<ch::utf8, rest::binary>>, acc) do
    parse_quoted_value(rest, acc <> <<ch::utf8>>)
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp validate_record(record, schema) do
    Enum.flat_map(schema, fn field ->
      value = Map.get(record, field.name)
      validate_field(value, field)
    end)
  end

  defp validate_field(value, field) do
    required? = Map.get(field, :required, true)
    type = Map.get(field, :type, :string)
    format = Map.get(field, :format, nil)

    # nil means key was missing; "" means key was present but empty
    absent? = is_nil(value) or value == ""

    required_errors =
      if required? and absent? do
        [{field.name, "is required"}]
      else
        []
      end

    # Type and format checks only apply to non-empty values.
    type_errors =
      if not absent? do
        check_type(value, type, field.name)
      else
        []
      end

    format_errors =
      if not absent? and format != nil do
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
      match?({_f, ""}, Float.parse(value)) -> []
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

  defp check_format(value, :ipv4, name) do
    check_format(value, @ipv4_regex, name)
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