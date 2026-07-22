defmodule CsvImporter do
  @moduledoc """
  Imports CSV data and validates each row against a declarative schema.

  A schema is a list of field definition maps:

    * `:name` (required) — the column header name, as a string.
    * `:required` (optional, default `true`) — when true the value must be
      present and non-blank.
    * `:type` (optional, default `:string`) — one of `:string`, `:integer`,
      `:float`, `:boolean`.
    * `:format` (optional) — a `Regex` the value must match, or the atom
      `:email` for a built-in email pattern.

  Both `import_file/2` and `import_string/2` return
  `{:ok, valid_rows, error_report}` where `valid_rows` is a list of maps
  keyed by field name (only schema fields that appear in the CSV headers)
  and `error_report` is a list of `{row_number, field_name, message}`
  tuples. Row numbers are 1-based and count data rows only — the header
  row is not counted.

  ## Example

      iex> schema = [%{name: "age", type: :integer}]
      iex> CsvImporter.import_string("age\\n30\\n", schema)
      {:ok, [%{"age" => "30"}], []}

  """

  NimbleCSV.define(CsvImporter.Parser, separator: ",", escape: "\"")

  alias CsvImporter.Parser

  @bom "\uFEFF"

  @email_regex ~r/^[^\s@]+@[^\s@,]+\.[A-Za-z]{2,}$/

  @boolean_values ~w(true false 1 0)

  @typedoc "A single field definition within a schema."
  @type field :: %{
          required(:name) => String.t(),
          optional(:required) => boolean(),
          optional(:type) => :string | :integer | :float | :boolean,
          optional(:format) => Regex.t() | :email
        }

  @typedoc "A list of field definitions."
  @type schema :: [field()]

  @typedoc "A validated row: field name => trimmed string value."
  @type row :: %{String.t() => String.t()}

  @typedoc "`{row_number, field_name, message}` for one validation failure."
  @type error :: {pos_integer(), String.t(), String.t()}

  @doc """
  Reads the CSV file at `file_path` and validates every data row against `schema`.

  Returns `{:ok, valid_rows, error_report}` on success, `{:error, :file_not_found}`
  when the path does not exist, and `{:error, :empty_file}` when the file is
  zero bytes.
  """
  @spec import_file(Path.t(), schema()) ::
          {:ok, [row()], [error()]} | {:error, :file_not_found | :empty_file}
  def import_file(file_path, schema) when is_binary(file_path) and is_list(schema) do
    case File.read(file_path) do
      {:ok, contents} -> import_string(contents, schema)
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, _reason} -> {:error, :file_not_found}
    end
  end

  @doc """
  Validates the CSV content in `csv_string` against `schema`.

  Behaves exactly like `import_file/2` but takes the CSV content directly.
  Returns `{:error, :empty_file}` for an empty binary.
  """
  @spec import_string(binary(), schema()) :: {:ok, [row()], [error()]} | {:error, :empty_file}
  def import_string("", schema) when is_list(schema), do: {:error, :empty_file}

  def import_string(csv_string, schema) when is_binary(csv_string) and is_list(schema) do
    csv_string
    |> strip_bom()
    |> parse_rows()
    |> case do
      [] ->
        {:ok, [], []}

      [headers | data_rows] ->
        fields = active_fields(schema, headers)
        {valid, errors} = process_rows(data_rows, headers, fields)
        {:ok, valid, errors}
    end
  end

  # -- Parsing ---------------------------------------------------------------

  @spec strip_bom(binary()) :: binary()
  defp strip_bom(@bom <> rest), do: rest
  defp strip_bom(contents), do: contents

  @spec parse_rows(binary()) :: [[String.t()]]
  defp parse_rows(contents) do
    contents
    |> Parser.parse_string(skip_headers: false)
    |> Enum.reject(&blank_row?/1)
  end

  @spec blank_row?([String.t()]) :: boolean()
  defp blank_row?(row), do: Enum.all?(row, &(String.trim(&1) == ""))

  # -- Schema ----------------------------------------------------------------

  # Keep only schema fields whose name appears in the headers, remembering the
  # column index each one maps to. Header columns absent from the schema are
  # dropped implicitly.
  @spec active_fields(schema(), [String.t()]) :: [{non_neg_integer(), field()}]
  defp active_fields(schema, headers) do
    index_by_name =
      headers
      |> Enum.map(&String.trim/1)
      |> Enum.with_index()
      |> Map.new()

    for field <- schema,
        index = Map.get(index_by_name, field.name),
        not is_nil(index),
        do: {index, field}
  end

  # -- Row processing --------------------------------------------------------

  @spec process_rows([[String.t()]], [String.t()], [{non_neg_integer(), field()}]) ::
          {[row()], [error()]}
  defp process_rows(data_rows, headers, fields) do
    column_count = length(headers)

    {valid, errors} =
      data_rows
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {raw_row, row_number}, {valid, errors} ->
        values = normalize_row(raw_row, column_count)
        {row, row_errors} = validate_row(values, fields, row_number)

        case row_errors do
          [] -> {[row | valid], errors}
          _ -> {valid, [row_errors | errors]}
        end
      end)

    {Enum.reverse(valid), errors |> Enum.reverse() |> List.flatten()}
  end

  # Pad short rows with empty strings, drop extra columns, trim every value.
  @spec normalize_row([String.t()], non_neg_integer()) :: [String.t()]
  defp normalize_row(raw_row, column_count) do
    raw_row
    |> Enum.take(column_count)
    |> Enum.map(&String.trim/1)
    |> then(&(&1 ++ List.duplicate("", column_count - length(&1))))
  end

  @spec validate_row([String.t()], [{non_neg_integer(), field()}], pos_integer()) ::
          {row(), [error()]}
  defp validate_row(values, fields, row_number) do
    {row, errors} =
      Enum.reduce(fields, {%{}, []}, fn {index, field}, {row, errors} ->
        value = Enum.at(values, index, "")

        field_errors =
          field
          |> validate_field(value)
          |> Enum.map(&{row_number, field.name, &1})

        {Map.put(row, field.name, value), field_errors ++ errors}
      end)

    {row, Enum.reverse(errors)}
  end

  # -- Field validation ------------------------------------------------------

  @spec validate_field(field(), String.t()) :: [String.t()]
  defp validate_field(field, value) do
    if value == "" do
      if required?(field), do: ["is required"], else: []
    else
      Enum.reject(
        [type_error(type(field), value), format_error(Map.get(field, :format), value)],
        &is_nil/1
      )
    end
  end

  @spec required?(field()) :: boolean()
  defp required?(field), do: Map.get(field, :required, true)

  @spec type(field()) :: :string | :integer | :float | :boolean
  defp type(field), do: Map.get(field, :type, :string)

  @spec type_error(atom(), String.t()) :: String.t() | nil
  defp type_error(:string, _value), do: nil

  defp type_error(:integer, value) do
    if valid_integer?(value), do: nil, else: "must be a valid integer"
  end

  defp type_error(:float, value) do
    if valid_float?(value), do: nil, else: "must be a valid float"
  end

  defp type_error(:boolean, value) do
    if String.downcase(value) in @boolean_values, do: nil, else: "must be a valid boolean"
  end

  defp type_error(_other, _value), do: nil

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

  @spec format_error(Regex.t() | :email | nil, String.t()) :: String.t() | nil
  defp format_error(nil, _value), do: nil
  defp format_error(:email, value), do: format_error(@email_regex, value)

  defp format_error(%Regex{} = regex, value) do
    if Regex.match?(regex, value), do: nil, else: "does not match expected format"
  end

  defp format_error(_other, _value), do: nil
end