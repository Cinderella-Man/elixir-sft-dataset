defmodule JsonlImporter do
  @moduledoc """
  Imports JSONL (JSON Lines) data and validates every record against a schema.

  A schema is a list of field definition maps:

    * `:name` (required) — the field key as a string.
    * `:required` (optional, default `true`) — the field must be present, non-null and,
      for strings, non-empty once trimmed.
    * `:type` (optional, default `:string`) — one of `:string`, `:integer`, `:float`,
      `:boolean` or `:list`.
    * `:format` (optional) — a `Regex` the string representation must match, or the atom
      `:email` for a built-in email pattern.

  Importing returns `{:ok, valid_records, error_report}` where `valid_records` is a list of
  maps (field name => decoded value) holding only schema fields, and `error_report` is a list
  of `{line_number, field_name, error_message}` tuples for every validation failure.

  Line numbers are 1-based and count only non-blank lines. Blank (empty or whitespace-only)
  lines are skipped entirely. A leading UTF-8 byte order mark is stripped. A line that is not
  valid JSON yields a single `{line_number, "_line", "invalid JSON"}` error.

      iex> schema = [%{name: "id", type: :integer}, %{name: "email", format: :email}]
      iex> JsonlImporter.import_string(~s({"id": 1, "email": "a@b.com"}), schema)
      {:ok, [%{"id" => 1, "email" => "a@b.com"}], []}
  """

  @bom "\uFEFF"
  @line_field "_line"

  @email_regex ~r/^[[:alnum:]!#$%&'*+\/=?^_`{|}~-]+(?:\.[[:alnum:]!#$%&'*+\/=?^_`{|}~-]+)*@[[:alnum:]](?:[[:alnum:]-]*[[:alnum:]])?(?:\.[[:alnum:]](?:[[:alnum:]-]*[[:alnum:]])?)+$/

  @type field_def :: %{
          required(:name) => String.t(),
          optional(:required) => boolean(),
          optional(:type) => field_type(),
          optional(:format) => Regex.t() | :email
        }
  @type field_type :: :string | :integer | :float | :boolean | :list
  @type record :: %{optional(String.t()) => term()}
  @type error :: {pos_integer(), String.t(), String.t()}
  @type result :: {:ok, [record()], [error()]} | {:error, :file_not_found | :empty_file}

  @doc """
  Reads the JSONL file at `file_path` and validates each record against `schema`.

  Returns `{:ok, valid_records, error_report}` on success, `{:error, :file_not_found}` when the
  path does not exist, and `{:error, :empty_file}` when the file is zero bytes or holds no
  non-blank lines.
  """
  @spec import_file(Path.t(), [field_def()]) :: result()
  def import_file(file_path, schema) when is_binary(file_path) and is_list(schema) do
    case File.read(file_path) do
      {:ok, ""} -> {:error, :empty_file}
      {:ok, contents} -> import_string(contents, schema)
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, _reason} -> {:error, :file_not_found}
    end
  end

  @doc """
  Validates the JSONL content held in `jsonl_string` against `schema`.

  Behaves exactly like `import_file/2` but takes the content directly, which is convenient for
  tests. Returns `{:error, :empty_file}` when the string holds no non-blank lines.
  """
  @spec import_string(binary(), [field_def()]) :: result()
  def import_string(jsonl_string, schema) when is_binary(jsonl_string) and is_list(schema) do
    lines =
      jsonl_string
      |> strip_bom()
      |> String.split(~r/\r?\n/)
      |> Enum.reject(&blank?/1)

    case lines do
      [] ->
        {:error, :empty_file}

      lines ->
        normalized = Enum.map(schema, &normalize_field/1)

        {records, errors} =
          lines
          |> Enum.with_index(1)
          |> Enum.reduce({[], []}, fn {line, number}, acc ->
            process_line(line, number, normalized, acc)
          end)

        {:ok, Enum.reverse(records), Enum.reverse(errors)}
    end
  end

  # -- line handling ---------------------------------------------------------

  @spec process_line(String.t(), pos_integer(), [map()], {[record()], [error()]}) ::
          {[record()], [error()]}
  defp process_line(line, number, schema, {records, errors}) do
    case Jason.decode(line) do
      {:ok, object} when is_map(object) ->
        case validate_record(object, number, schema) do
          {:ok, record} -> {[record | records], errors}
          {:error, line_errors} -> {records, Enum.reverse(line_errors) ++ errors}
        end

      {:ok, _other} ->
        {records, [{number, @line_field, "invalid JSON"} | errors]}

      {:error, _reason} ->
        {records, [{number, @line_field, "invalid JSON"} | errors]}
    end
  end

  @spec validate_record(map(), pos_integer(), [map()]) :: {:ok, record()} | {:error, [error()]}
  defp validate_record(object, number, schema) do
    {record, errors} =
      Enum.reduce(schema, {%{}, []}, fn field, {record, errors} ->
        value = normalize_value(Map.get(object, field.name, :__missing__))

        case validate_field(field, value) do
          [] -> {maybe_put(record, field.name, value), errors}
          messages -> {record, Enum.map(messages, &{number, field.name, &1}) ++ errors}
        end
      end)

    case errors do
      [] -> {:ok, record}
      errors -> {:error, errors}
    end
  end

  @spec maybe_put(record(), String.t(), term()) :: record()
  defp maybe_put(record, _name, :__missing__), do: record
  defp maybe_put(record, name, value), do: Map.put(record, name, value)

  # Strings are trimmed before validation so that surrounding whitespace never leaks into
  # required, type or format checks (nor into the resulting valid records).
  @spec normalize_value(term()) :: term()
  defp normalize_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_value(value), do: value

  # -- field validation ------------------------------------------------------

  @spec validate_field(map(), term()) :: [String.t()]
  defp validate_field(field, value) do
    if blank_value?(value) do
      if field.required, do: ["is required"], else: []
    else
      type_errors(field.type, value) ++ format_errors(field, value)
    end
  end

  @spec blank_value?(term()) :: boolean()
  defp blank_value?(:__missing__), do: true
  defp blank_value?(nil), do: true
  defp blank_value?(""), do: true
  defp blank_value?(_value), do: false

  @spec type_errors(field_type(), term()) :: [String.t()]
  defp type_errors(type, value) do
    if valid_type?(type, value), do: [], else: ["must be a valid #{type}"]
  end

  @spec valid_type?(field_type(), term()) :: boolean()
  defp valid_type?(:string, value), do: is_binary(value)
  defp valid_type?(:integer, value) when is_integer(value), do: true
  defp valid_type?(:integer, value) when is_float(value), do: whole_float?(value)
  defp valid_type?(:integer, _value), do: false
  defp valid_type?(:float, value), do: is_integer(value) or is_float(value)
  defp valid_type?(:boolean, value), do: is_boolean(value)
  defp valid_type?(:list, value), do: is_list(value)
  defp valid_type?(_type, _value), do: false

  @spec whole_float?(float()) :: boolean()
  defp whole_float?(value) do
    case Float.round(value) - value do
      +0.0 -> true
      -0.0 -> true
      _other -> false
    end
  end

  # Format checks only apply to string-typed fields; other types are left untouched.
  @spec format_errors(map(), term()) :: [String.t()]
  defp format_errors(%{format: nil}, _value), do: []
  defp format_errors(%{type: :string, format: regex}, value) when is_binary(value) do
    if Regex.match?(regex, value), do: [], else: ["does not match expected format"]
  end

  defp format_errors(_field, _value), do: []

  # -- schema normalization --------------------------------------------------

  @spec normalize_field(field_def()) :: map()
  defp normalize_field(%{name: name} = field) when is_binary(name) do
    %{
      name: name,
      required: Map.get(field, :required, true),
      type: Map.get(field, :type) || :string,
      format: normalize_format(Map.get(field, :format))
    }
  end

  @spec normalize_format(Regex.t() | :email | nil) :: Regex.t() | nil
  defp normalize_format(nil), do: nil
  defp normalize_format(:email), do: @email_regex
  defp normalize_format(%Regex{} = regex), do: regex

  # -- helpers ---------------------------------------------------------------

  @spec strip_bom(binary()) :: binary()
  defp strip_bom(@bom <> rest), do: rest
  defp strip_bom(contents), do: contents

  @spec blank?(String.t()) :: boolean()
  defp blank?(line), do: String.trim(line) == ""
end