defmodule LogfmtValidator do
  @moduledoc """
  Reads and validates logfmt-formatted data against a declarative schema.

  Logfmt is a structured logging format where each line contains space-separated
  `key=value` pairs. Values containing spaces must be double-quoted:

      level=info host=web01 method=GET path=/api/users duration=42 success=true
      level=error host=web02 path="/api/data import" duration=abc success=false

  A schema is a list of field definition maps:

    * `:name` (required) — the key name, as a string
    * `:required` (optional, default `true`) — key must be present and non-empty
    * `:type` (optional, default `:string`) — `:string`, `:integer`, `:float` or `:boolean`
    * `:format` (optional) — a `Regex` the value must match, or the atom `:ipv4`

  Validation produces `{:ok, valid_records, error_report}` where `valid_records`
  is a list of maps (field name => string value) restricted to schema fields, and
  `error_report` is a list of `{line_number, field_name, error_message}` tuples.

  ## Examples

      iex> schema = [%{name: "level"}, %{name: "duration", type: :integer}]
      iex> LogfmtValidator.validate_string("level=info duration=42", schema)
      {:ok, [%{"level" => "info", "duration" => "42"}], []}

      iex> schema = [%{name: "duration", type: :integer}]
      iex> LogfmtValidator.validate_string("duration=abc", schema)
      {:ok, [], [{1, "duration", "must be a valid integer"}]}
  """

  @bom "\uFEFF"

  @ipv4_regex ~r/^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$/

  @boolean_values ~w(true false 1 0)

  @typedoc "A single schema field definition."
  @type field :: %{
          required(:name) => String.t(),
          optional(:required) => boolean(),
          optional(:type) => :string | :integer | :float | :boolean,
          optional(:format) => Regex.t() | :ipv4
        }

  @typedoc "A list of schema field definitions."
  @type schema :: [field()]

  @typedoc "A validated record: schema field name => raw string value."
  @type record :: %{optional(String.t()) => String.t()}

  @typedoc "A single validation failure: `{line_number, field_name, message}`."
  @type error :: {pos_integer(), String.t(), String.t()}

  @doc """
  Reads the logfmt file at `file_path` and validates every non-blank line against `schema`.

  Returns `{:ok, valid_records, error_report}` on success, `{:error, :file_not_found}` when
  the path does not exist, and `{:error, :empty_file}` when the file is zero bytes or has no
  non-blank lines.

  ## Examples

      LogfmtValidator.validate_file("app.log", [%{name: "level"}])
      #=> {:ok, [%{"level" => "info"}], []}
  """
  @spec validate_file(Path.t(), schema()) ::
          {:ok, [record()], [error()]} | {:error, :file_not_found | :empty_file}
  def validate_file(file_path, schema) when is_binary(file_path) and is_list(schema) do
    case File.read(file_path) do
      {:ok, ""} -> {:error, :empty_file}
      {:ok, contents} -> validate_string(contents, schema)
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, _reason} -> {:error, :file_not_found}
    end
  end

  @doc """
  Validates `logfmt_string` against `schema`, treating each non-blank line as one record.

  Behaves exactly like `validate_file/2` but takes the logfmt content directly. Returns
  `{:error, :empty_file}` when the string contains no non-blank lines.

  ## Examples

      iex> LogfmtValidator.validate_string("host=web01", [%{name: "host"}])
      {:ok, [%{"host" => "web01"}], []}

      iex> LogfmtValidator.validate_string("   \\n", [%{name: "host"}])
      {:error, :empty_file}
  """
  @spec validate_string(binary(), schema()) ::
          {:ok, [record()], [error()]} | {:error, :empty_file}
  def validate_string(logfmt_string, schema) when is_binary(logfmt_string) and is_list(schema) do
    normalized = Enum.map(schema, &normalize_field/1)

    lines =
      logfmt_string
      |> strip_bom()
      |> String.split(["\r\n", "\n", "\r"])
      |> Enum.reject(&blank?/1)

    case lines do
      [] ->
        {:error, :empty_file}

      lines ->
        {records, errors} =
          lines
          |> Enum.with_index(1)
          |> Enum.reduce({[], []}, fn {line, line_number}, acc ->
            process_line(line, line_number, normalized, acc)
          end)

        {:ok, Enum.reverse(records), Enum.reverse(errors)}
    end
  end

  # --- Line processing -------------------------------------------------------

  @spec process_line(String.t(), pos_integer(), schema(), {[record()], [error()]}) ::
          {[record()], [error()]}
  defp process_line(line, line_number, schema, {records, errors}) do
    case parse_line(line) do
      {:ok, pairs} ->
        case validate_record(pairs, schema, line_number) do
          {:ok, record} -> {[record | records], errors}
          {:error, line_errors} -> {records, Enum.reverse(line_errors) ++ errors}
        end

      :error ->
        {records, [{line_number, "_line", "malformed logfmt line"} | errors]}
    end
  end

  @spec validate_record(map(), schema(), pos_integer()) ::
          {:ok, record()} | {:error, [error()]}
  defp validate_record(pairs, schema, line_number) do
    {record, errors} =
      Enum.reduce(schema, {%{}, []}, fn field, {record, errors} ->
        value = Map.get(pairs, field.name)
        field_errors = validate_field(field, value)

        record =
          if is_binary(value), do: Map.put(record, field.name, value), else: record

        {record, errors ++ Enum.map(field_errors, &{line_number, field.name, &1})}
      end)

    case errors do
      [] -> {:ok, record}
      errors -> {:error, errors}
    end
  end

  @spec validate_field(map(), String.t() | nil) :: [String.t()]
  defp validate_field(field, value) do
    cond do
      empty_value?(value) and field.required ->
        ["is required"]

      empty_value?(value) ->
        []

      true ->
        type_errors(field.type, value) ++ format_errors(field.format, value)
    end
  end

  @spec empty_value?(String.t() | nil) :: boolean()
  defp empty_value?(nil), do: true
  defp empty_value?(""), do: true
  defp empty_value?(_value), do: false

  @spec type_errors(atom(), String.t()) :: [String.t()]
  defp type_errors(:string, _value), do: []

  defp type_errors(:integer, value) do
    if valid_integer?(value), do: [], else: ["must be a valid integer"]
  end

  defp type_errors(:float, value) do
    if valid_float?(value), do: [], else: ["must be a valid float"]
  end

  defp type_errors(:boolean, value) do
    if String.downcase(value) in @boolean_values, do: [], else: ["must be a valid boolean"]
  end

  @spec format_errors(Regex.t() | nil, String.t()) :: [String.t()]
  defp format_errors(nil, _value), do: []

  defp format_errors(%Regex{} = regex, value) do
    if Regex.match?(regex, value), do: [], else: ["does not match expected format"]
  end

  @spec valid_integer?(String.t()) :: boolean()
  defp valid_integer?(value) do
    _ = String.to_integer(value)
    true
  rescue
    ArgumentError -> false
  end

  @spec valid_float?(String.t()) :: boolean()
  defp valid_float?(value) do
    _ = String.to_float(value)
    true
  rescue
    ArgumentError -> valid_integer?(value)
  end

  # --- Schema normalization --------------------------------------------------

  @spec normalize_field(map()) :: map()
  defp normalize_field(%{name: name} = field) when is_binary(name) do
    %{
      name: name,
      required: Map.get(field, :required, true),
      type: normalize_type(Map.get(field, :type, :string)),
      format: normalize_format(Map.get(field, :format))
    }
  end

  @spec normalize_type(atom()) :: atom()
  defp normalize_type(type) when type in [:string, :integer, :float, :boolean], do: type

  defp normalize_type(type) do
    raise ArgumentError, "unsupported schema type: #{inspect(type)}"
  end

  @spec normalize_format(Regex.t() | :ipv4 | nil) :: Regex.t() | nil
  defp normalize_format(nil), do: nil
  defp normalize_format(:ipv4), do: @ipv4_regex
  defp normalize_format(%Regex{} = regex), do: regex

  defp normalize_format(other) do
    raise ArgumentError, "unsupported schema format: #{inspect(other)}"
  end

  # --- Parsing ---------------------------------------------------------------

  @spec strip_bom(binary()) :: binary()
  defp strip_bom(@bom <> rest), do: rest
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(contents), do: contents

  @spec blank?(String.t()) :: boolean()
  defp blank?(line), do: String.trim(line) == ""

  @doc false
  @spec parse_line(String.t()) :: {:ok, map()} | :error
  defp parse_line(line) do
    line
    |> String.trim()
    |> parse_pairs(%{})
  end

  @spec parse_pairs(String.t(), map()) :: {:ok, map()} | :error
  defp parse_pairs("", acc), do: {:ok, acc}

  defp parse_pairs(<<c::utf8, rest::binary>>, acc) when c in [?\s, ?\t] do
    parse_pairs(rest, acc)
  end

  defp parse_pairs(input, acc) do
    {key, rest} = parse_key(input, "")

    case String.trim(key) do
      "" ->
        :error

      key ->
        case rest do
          "=" <> value_rest ->
            case parse_value(value_rest) do
              {:ok, value, remainder} -> parse_pairs(remainder, Map.put(acc, key, value))
              :error -> :error
            end

          remainder ->
            parse_pairs(remainder, Map.put(acc, key, "true"))
        end
    end
  end

  # Reads a key up to the next `=` or whitespace boundary.
  @spec parse_key(String.t(), String.t()) :: {String.t(), String.t()}
  defp parse_key("", acc), do: {acc, ""}
  defp parse_key(<<?=, _::binary>> = rest, acc), do: {acc, rest}

  defp parse_key(<<c::utf8, rest::binary>>, acc) when c in [?\s, ?\t] do
    skip_to_equals(rest, acc)
  end

  defp parse_key(<<c::utf8, rest::binary>>, acc) do
    parse_key(rest, acc <> <<c::utf8>>)
  end

  # After trailing whitespace in a key, an `=` still binds to it (`key = value`);
  # anything else means the key was a bare boolean flag.
  @spec skip_to_equals(String.t(), String.t()) :: {String.t(), String.t()}
  defp skip_to_equals(<<c::utf8, rest::binary>>, acc) when c in [?\s, ?\t] do
    skip_to_equals(rest, acc)
  end

  defp skip_to_equals(<<?=, _::binary>> = rest, acc), do: {acc, rest}
  defp skip_to_equals(rest, acc), do: {acc, " " <> rest}

  # Values may be quoted (with escapes) or bare; leading spaces before a value are skipped
  # only when they precede a quoted value or a token on the same logical pair.
  @spec parse_value(String.t()) :: {:ok, String.t(), String.t()} | :error
  defp parse_value(<<c::utf8, rest::binary>>) when c in [?\s, ?\t], do: parse_value(rest)
  defp parse_value(<<?", rest::binary>>), do: parse_quoted(rest, "")
  defp parse_value(input), do: parse_bare(input, "")

  @spec parse_quoted(String.t(), String.t()) :: {:ok, String.t(), String.t()} | :error
  defp parse_quoted("", _acc), do: :error
  defp parse_quoted(<<?\\, ?", rest::binary>>, acc), do: parse_quoted(rest, acc <> "\"")
  defp parse_quoted(<<?\\, ?\\, rest::binary>>, acc), do: parse_quoted(rest, acc <> "\\")
  defp parse_quoted(<<?", rest::binary>>, acc), do: {:ok, acc, rest}

  defp parse_quoted(<<c::utf8, rest::binary>>, acc) do
    parse_quoted(rest, acc <> <<c::utf8>>)
  end

  @spec parse_bare(String.t(), String.t()) :: {:ok, String.t(), String.t()}
  defp parse_bare("", acc), do: {:ok, String.trim(acc), ""}

  defp parse_bare(<<c::utf8, rest::binary>>, acc) when c in [?\s, ?\t] do
    {:ok, String.trim(acc), rest}
  end

  defp parse_bare(<<?", _::binary>>, _acc), do: {:ok, "", ""}

  defp parse_bare(<<c::utf8, rest::binary>>, acc) do
    parse_bare(rest, acc <> <<c::utf8>>)
  end
end