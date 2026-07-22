defmodule CsvImporter do
  @moduledoc """
  Imports CSV data and validates every data row against a declarative schema.

  A schema is a list of field definitions (maps). Each definition supports:

    * `:name` (required) — the column header name, as a string.
    * `:required` (optional, default `true`) — when `true`, the value must be
      present and non-empty.
    * `:type` (optional, default `:string`) — one of `:string`, `:integer`,
      `:float`, `:boolean`.
    * `:format` (optional) — a `Regex` the value must match, or the atom
      `:email` for a built-in email pattern.

  Both `import_file/2` and `import_string/2` return
  `{:ok, valid_rows, error_report}` on success, where `valid_rows` is a list of
  `%{header => value}` maps and `error_report` is a list of
  `{row_number, field_name, error_message}` tuples. Data rows are numbered
  starting at `1`; the header row is not counted.

  Parsing is delegated to `NimbleCSV`, so quoted fields containing commas or
  embedded newlines are handled per RFC 4180.
  """

  NimbleCSV.define(CsvImporter.Parser, separator: ",", escape: "\"")

  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @typedoc "A single validation failure: row number, field name, message."
  @type error :: {pos_integer(), String.t(), String.t()}

  @typedoc "A list of field-definition maps."
  @type schema :: [map()]

  @doc """
  Reads the CSV file at `file_path` and validates it against `schema`.

  Returns `{:ok, valid_rows, error_report}` on success, `{:error,
  :file_not_found}` when the path does not exist, and `{:error, :empty_file}`
  when the file is zero bytes.
  """
  @spec import_file(Path.t(), schema()) ::
          {:ok, [map()], [error()]} | {:error, :file_not_found | :empty_file}
  def import_file(file_path, schema) do
    case File.read(file_path) do
      {:ok, ""} -> {:error, :empty_file}
      {:ok, content} -> do_import(content, schema)
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, _reason} -> {:error, :file_not_found}
    end
  end

  @doc """
  Validates the CSV content in `csv_string` against `schema`.

  Behaves exactly like `import_file/2` but takes the CSV as a binary. An empty
  string returns `{:error, :empty_file}`.
  """
  @spec import_string(binary(), schema()) ::
          {:ok, [map()], [error()]} | {:error, :empty_file}
  def import_string("", _schema), do: {:error, :empty_file}
  def import_string(csv_string, schema), do: do_import(csv_string, schema)

  # -- Internal --------------------------------------------------------------

  @spec do_import(binary(), schema()) :: {:ok, [map()], [error()]}
  defp do_import(content, schema) do
    content
    |> strip_bom()
    |> CsvImporter.Parser.parse_string(skip_headers: false)
    |> case do
      [] ->
        {:ok, [], []}

      [header | data_rows] ->
        headers = Enum.map(header, &String.trim/1)
        process_rows(data_rows, headers, schema)
    end
  end

  @spec strip_bom(binary()) :: binary()
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(content), do: content

  @spec process_rows([[binary()]], [String.t()], schema()) ::
          {:ok, [map()], [error()]}
  defp process_rows(data_rows, headers, schema) do
    {valid, errors} =
      data_rows
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {row, row_number}, {valid_acc, error_acc} ->
        row_map = build_row_map(row, headers)

        case validate_row(row_map, schema, row_number) do
          [] -> {[row_map | valid_acc], error_acc}
          row_errors -> {valid_acc, [row_errors | error_acc]}
        end
      end)

    flat_errors = errors |> Enum.reverse() |> List.flatten()
    {:ok, Enum.reverse(valid), flat_errors}
  end

  @spec build_row_map([binary()], [String.t()]) :: map()
  defp build_row_map(row, headers) do
    headers
    |> Enum.with_index()
    |> Map.new(fn {header, index} ->
      value = row |> Enum.at(index, "") |> String.trim()
      {header, value}
    end)
  end

  @spec validate_row(map(), schema(), pos_integer()) :: [error()]
  defp validate_row(row_map, schema, row_number) do
    Enum.flat_map(schema, fn field ->
      name = Map.fetch!(field, :name)
      value = Map.get(row_map, name, "")
      validate_field(field, name, value, row_number)
    end)
  end

  @spec validate_field(map(), String.t(), String.t(), pos_integer()) :: [error()]
  defp validate_field(field, name, value, row_number) do
    required = Map.get(field, :required, true)
    type = Map.get(field, :type, :string)
    format = Map.get(field, :format)

    cond do
      String.trim(value) == "" and required ->
        [{row_number, name, "is required"}]

      String.trim(value) == "" ->
        []

      true ->
        type_errors(type, value, name, row_number) ++
          format_errors(format, value, name, row_number)
    end
  end

  @spec type_errors(atom(), String.t(), String.t(), pos_integer()) :: [error()]
  defp type_errors(:string, _value, _name, _row), do: []

  defp type_errors(:integer, value, name, row) do
    if valid_integer?(value),
      do: [],
      else: [{row, name, "must be a valid integer"}]
  end

  defp type_errors(:float, value, name, row) do
    if valid_float?(value),
      do: [],
      else: [{row, name, "must be a valid float"}]
  end

  defp type_errors(:boolean, value, name, row) do
    if valid_boolean?(value),
      do: [],
      else: [{row, name, "must be a valid boolean"}]
  end

  defp type_errors(_type, _value, _name, _row), do: []

  @spec format_errors(term(), String.t(), String.t(), pos_integer()) :: [error()]
  defp format_errors(nil, _value, _name, _row), do: []

  defp format_errors(:email, value, name, row) do
    format_errors(@email_regex, value, name, row)
  end

  defp format_errors(%Regex{} = regex, value, name, row) do
    if Regex.match?(regex, value),
      do: [],
      else: [{row, name, "does not match expected format"}]
  end

  defp format_errors(_other, _value, _name, _row), do: []

  @spec valid_integer?(String.t()) :: boolean()
  defp valid_integer?(value) do
    _ = String.to_integer(value)
    true
  rescue
    ArgumentError -> false
  end

  @spec valid_float?(String.t()) :: boolean()
  defp valid_float?(value) do
    valid_via_float?(value) or valid_integer?(value)
  end

  @spec valid_via_float?(String.t()) :: boolean()
  defp valid_via_float?(value) do
    _ = String.to_float(value)
    true
  rescue
    ArgumentError -> false
  end

  @spec valid_boolean?(String.t()) :: boolean()
  defp valid_boolean?(value) do
    String.downcase(value) in ["true", "false", "1", "0"]
  end
end