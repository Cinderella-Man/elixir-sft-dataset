# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `import_string` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `JsonlImporter` that reads a JSONL (JSON Lines) file, validates each record against a provided schema, and returns a structured result splitting valid records from errors.

I need these functions in the public API:

- `JsonlImporter.import_file(file_path, schema)` which reads the JSONL file at the given path and validates every line against the schema. It should return `{:ok, valid_records, error_report}` where `valid_records` is a list of maps (field name => decoded value) for records that passed all validations, in the order they appear in the input, and `error_report` is a list of `{line_number, field_name, error_message}` tuples describing every validation failure. Line numbers should be 1-based. If the file doesn't exist, return `{:error, :file_not_found}`. If the file is empty (zero bytes), return `{:error, :empty_file}`.

- `JsonlImporter.import_string(jsonl_string, schema)` which does the same thing but accepts the JSONL content as a binary string instead of a file path. This is useful for testing.

The schema should be a list of field definitions, where each field is a map with these keys:
- `:name` (required) — the field key as a string
- `:required` (optional, default `true`) — if true, the field must be present and non-null; for strings, it must also be non-empty/non-whitespace
- `:type` (optional, default `:string`) — one of `:string`, `:integer`, `:float`, `:boolean`, `:list`
- `:format` (optional) — a regex that the string representation of the field value must match. For convenience, also accept the atom `:email` which should use a reasonable email regex pattern.

Validation rules:
- Required fields that are missing from the JSON object, are `null`, or (for strings) are empty/whitespace-only should produce an error `"is required"`.
- Type checks: `:string` must be a JSON string, `:integer` must be a JSON number that is a whole number, `:float` must be a JSON number (integers are also accepted as valid floats), `:boolean` must be a JSON boolean (`true`/`false`), `:list` must be a JSON array. Type errors should read `"must be a valid <type>"`.
- Format checks only apply to string-typed fields and should produce `"does not match expected format"`.
- A single field can have multiple errors — report all of them, not just the first.
- Lines that are not valid JSON — or that parse to a valid JSON value that is not an object (for example an array like `[1, 2, 3]` or a bare scalar) — should produce a single error `{line_number, "_line", "invalid JSON"}` and be counted as invalid.

Edge cases to handle:
- UTF-8 BOM (`\xEF\xBB\xBF`) at the start of the file — strip it before parsing.
- Blank lines (empty or whitespace-only) should be silently skipped and not counted in line numbering.
- File with no non-blank lines after BOM stripping — return `{:error, :empty_file}`.
- Extra fields in the JSON object that are not in the schema should be silently ignored (not included in valid records).
- Whitespace around string values should be trimmed before validation, and the trimmed value is what appears in the returned valid record.

Use the Jason library for JSON parsing (`:jason` hex package). Do not use any other external dependencies. Give me the complete module in a single file.

## The module with `import_string` missing

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

  def import_string(jsonl_string, schema) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  # Strip a UTF-8 BOM if present.
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(other), do: other

  # Process all non-blank lines and validate each against the schema.
  defp process_lines(lines, schema) do
    {valid_records, error_report} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {line, line_num}, {valid_acc, err_acc} ->
        case Jason.decode(line) do
          {:ok, record} when is_map(record) ->
            errors = validate_record(record, schema)

            case errors do
              [] ->
                filtered = build_valid_record(record, schema)
                {[filtered | valid_acc], err_acc}

              _ ->
                tagged = Enum.map(errors, fn {field, msg} -> {line_num, field, msg} end)
                {valid_acc, err_acc ++ tagged}
            end

          {:ok, _not_a_map} ->
            {valid_acc, err_acc ++ [{line_num, "_line", "invalid JSON"}]}

          {:error, _} ->
            {valid_acc, err_acc ++ [{line_num, "_line", "invalid JSON"}]}
        end
      end)

    {:ok, Enum.reverse(valid_records), error_report}
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

Give me only the complete implementation of `import_string` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
