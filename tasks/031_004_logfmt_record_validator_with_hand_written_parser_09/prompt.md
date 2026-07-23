# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `parse_logfmt_line` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Write me an Elixir module called `LogfmtValidator` that reads a logfmt-formatted file (one record per line as `key=value` pairs), validates each record against a provided schema, and returns a structured result splitting valid records from errors.

Logfmt is a structured logging format where each line contains space-separated `key=value` pairs. Values containing spaces must be double-quoted. Example:
```
level=info host=web01 method=GET path=/api/users duration=42 success=true
level=error host=web02 method=POST path="/api/data import" duration=abc success=false
```

I need these functions in the public API:

- `LogfmtValidator.validate_file(file_path, schema)` which reads the logfmt file at the given path and validates every line against the schema. It should return `{:ok, valid_records, error_report}` where `valid_records` is a list of maps (field name => string value) for records that passed all validations, listed in the order those records appear in the input, and `error_report` is a list of `{line_number, field_name, error_message}` tuples describing every validation failure. Line numbers are 1-based. If the file doesn't exist, return `{:error, :file_not_found}`. If the file is empty (zero bytes), return `{:error, :empty_file}`.

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

## The module with `parse_logfmt_line` missing

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
    {valid_records, error_report} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {line, line_num}, {valid_acc, err_acc} ->
        case parse_logfmt_line(line) do
          {:ok, record} ->
            errors = validate_record(record, schema)

            case errors do
              [] ->
                filtered = build_valid_record(record, schema)
                {[filtered | valid_acc], err_acc}

              _ ->
                tagged = Enum.map(errors, fn {field, msg} -> {line_num, field, msg} end)
                {valid_acc, err_acc ++ tagged}
            end

          {:error, :malformed} ->
            {valid_acc, err_acc ++ [{line_num, "_line", "malformed logfmt line"}]}
        end
      end)

    {:ok, Enum.reverse(valid_records), error_report}
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

  def parse_logfmt_line(line) do
    # TODO
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
  # Unterminated quote
  defp parse_quoted_value("", _acc), do: :error

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

Reply with `parse_logfmt_line` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
