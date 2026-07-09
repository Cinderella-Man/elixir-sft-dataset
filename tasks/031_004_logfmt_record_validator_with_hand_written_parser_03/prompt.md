Implement the private `do_parse/2` function for the logfmt parser.

`do_parse/2` is the recursive engine that turns an already-trimmed logfmt line into a
map of `key => value` pairs. Its first argument is the remaining unparsed portion of the
line (a binary), and its second argument `acc` is the map of pairs accumulated so far. It
must return `{:ok, acc}` when the whole input has been consumed, or `:error` if the input
is malformed (for example, an unterminated quoted value).

Behavior it must implement:

- If the input is the empty string `""`, parsing is done — return `{:ok, acc}`.
- Otherwise, strip any leading whitespace from the input. If what remains is empty, return
  `{:ok, acc}`.
- Parse the next key using `parse_key/1`. If `parse_key/1` returns `:error`, propagate
  `:error`. On success it yields `{:ok, key, rest}`.
- Trim leading whitespace from `rest`, then decide based on what follows the key:
  - If `rest` begins with `"="`, take the text after the `=` sign (`after_eq`). Do **not**
    trim leading whitespace from `after_eq` — a leading space there means this key's value
    is empty. Parse it with `parse_value/1`. If that returns `:error`, propagate `:error`.
    On `{:ok, value, remaining}`, recurse via `do_parse/2` on `remaining`, inserting the
    trimmed key mapped to the trimmed value into `acc` (last occurrence of a duplicate key
    wins, which `Map.put/3` gives you naturally).
  - Otherwise the key is a bare boolean flag: recurse via `do_parse/2` on `rest`, inserting
    the trimmed key mapped to `"true"` into `acc`.

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
  defp do_parse(input, acc) do
    # TODO
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