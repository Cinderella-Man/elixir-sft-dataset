Implement the private `process_lines/2` function. It receives `lines` (a list of
non-blank JSONL strings, already BOM-stripped and with blank lines removed) and
`schema` (the list of field-definition maps). It must walk every line, pairing it
with a 1-based line number (use `Enum.with_index(1)`), and accumulate two things:
a list of valid records and a flat error report.

For each line, decode it with `Jason.decode/1`:

- On `{:ok, record}` where `record` is a map, validate it with
  `validate_record/2`. If validation returns no errors, build the filtered valid
  record with `build_valid_record/2` and add it to the valid accumulator. If
  validation returns errors, tag each `{field, msg}` with the current line number
  as `{line_num, field, msg}` and append those to the error accumulator.
- On `{:ok, _}` where the decoded value is *not* a map (e.g. a bare number or
  array), record a single `{line_num, "_line", "invalid JSON"}` error.
- On `{:error, _}` (the line is not valid JSON), record a single
  `{line_num, "_line", "invalid JSON"}` error.

Because valid records are prepended for efficiency, reverse them before returning.
The function returns `{:ok, valid_records, error_report}` with the valid records in
original line order and the error report listing every validation failure across all
lines.

```elixir
defmodule JsonlImporter do
  @moduledoc """
  Reads JSONL data (from a file or string), validates each record against a
  provided schema, and returns structured results splitting valid records from errors.

  ## Schema

  A schema is a list of field definition maps:

      [
        %{name: "email", required: true, type: :string, format: :email},
        %{name: "age",   required: true, type: :integer},
        %{name: "score", required: false, type: :float},
        %{name: "active", type: :boolean},
        %{name: "tags",  type: :list, required: false}
      ]

  Each field map supports:
    - `:name`     (required) — field key in the JSON object (string)
    - `:required` (optional, default `true`) — whether the field must be present and non-null
    - `:type`     (optional, default `:string`) — `:string | :integer | :float | :boolean | :list`
    - `:format`   (optional) — a `Regex` or the atom `:email` (only for `:string` type)
  """

  # A reasonable email regex — intentionally permissive.
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Import a JSONL file at `file_path`, validate every record against `schema`.

  Returns:
    - `{:ok, valid_records, error_report}` on success
    - `{:error, :file_not_found}` if the file does not exist
    - `{:error, :empty_file}` if the file is zero bytes or contains no non-blank lines
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
  Import JSONL content given directly as a binary string.

  Returns `{:ok, valid_records, error_report}` or `{:error, :empty_file}`.
  """
  @spec import_string(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :empty_file}
  def import_string(jsonl_string, schema) do
    stripped = strip_bom(jsonl_string)

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

  # Strip a UTF-8 BOM if present.
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(other), do: other

  defp process_lines(lines, schema) do
    # TODO
  end

  # Build a map containing only the fields specified in the schema.
  # String values are trimmed.
  defp build_valid_record(record, schema) do
    schema
    |> Enum.filter(fn field -> Map.has_key?(record, field.name) end)
    |> Enum.map(fn field ->
      value = Map.get(record, field.name)
      trimmed = if is_binary(value), do: String.trim(value), else: value
      {field.name, trimmed}
    end)
    |> Map.new()
  end

  # Validate a single record against the full schema.
  # Returns a list of {field_name, error_message} tuples (empty if valid).
  defp validate_record(record, schema) do
    Enum.flat_map(schema, fn field ->
      value = Map.get(record, field.name)
      validate_field(value, field)
    end)
  end

  # Validate a single field value against its field definition.
  defp validate_field(value, field) do
    required? = Map.get(field, :required, true)
    type = Map.get(field, :type, :string)
    format = Map.get(field, :format, nil)

    # Determine if value is "absent" for required checks.
    absent? = is_nil(value) or (is_binary(value) and String.trim(value) == "")

    required_errors =
      if required? and absent? do
        [{field.name, "is required"}]
      else
        []
      end

    # Type and format checks only apply to present, non-blank values.
    if absent? do
      required_errors
    else
      required_errors ++
        check_type(value, type, field.name) ++
        format_errors(value, type, format, field.name)
    end
  end

  # Format checks only apply to string-typed fields holding a string value.
  defp format_errors(value, :string, format, name)
       when is_binary(value) and not is_nil(format) do
    check_format(String.trim(value), format, name)
  end

  defp format_errors(_value, _type, _format, _name), do: []

  # Type checkers -------------------------------------------------------

  defp check_type(value, :string, _name) when is_binary(value), do: []
  defp check_type(_value, :string, name), do: [{name, "must be a valid string"}]

  defp check_type(value, :integer, _name) when is_integer(value), do: []

  defp check_type(value, :integer, name) when is_float(value) do
    # A JSON number that is a whole number is a valid :integer — 42.0 counts;
    # only a fractional part makes it a type error.
    if value == trunc(value) * 1.0 do
      []
    else
      [{name, "must be a valid integer"}]
    end
  end

  defp check_type(_value, :integer, name), do: [{name, "must be a valid integer"}]

  defp check_type(value, :float, _name) when is_float(value), do: []
  defp check_type(value, :float, _name) when is_integer(value), do: []
  defp check_type(_value, :float, name), do: [{name, "must be a valid float"}]

  defp check_type(value, :boolean, _name) when is_boolean(value), do: []
  defp check_type(_value, :boolean, name), do: [{name, "must be a valid boolean"}]

  defp check_type(value, :list, _name) when is_list(value), do: []
  defp check_type(_value, :list, name), do: [{name, "must be a valid list"}]

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