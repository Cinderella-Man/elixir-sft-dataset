defmodule CsvLoader do
  @moduledoc """
  Loads CSV data from a file or a binary string, validating and coercing each data row
  against a caller-supplied schema.

  A schema is a list of field definition maps:

    * `:name` (required) — the column header name, as a string.
    * `:key` (optional) — the atom key used in the resulting map. Defaults to
      `String.to_atom(name)`.
    * `:required` (optional, default `true`) — when true, the field must be present and
      non-empty.
    * `:type` (optional, default `:string`) — one of `:string`, `:integer`, `:float`,
      `:boolean`, `:date`, `:enum`.
    * `:values` (required for `:enum`) — the list of allowed string values.
    * `:default` (optional) — value substituted when an optional field is empty. Must
      already be the correct Elixir type.
    * `:format` (optional) — a `Regex` the raw (trimmed) string must match before coercion.

  Both entry points return `{:ok, valid_rows, error_report}` where `valid_rows` is a list
  of maps keyed by the schema's `:key` atoms, and `error_report` is a list of
  `{row_number, field_name, message}` tuples. Row numbers are 1-based over data rows only —
  the header row is not counted.
  """

  NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\"")

  @bom "\uFEFF"

  @type field_type :: :string | :integer | :float | :boolean | :date | :enum

  @type field_def :: %{
          required(:name) => String.t(),
          optional(:key) => atom(),
          optional(:required) => boolean(),
          optional(:type) => field_type(),
          optional(:values) => [String.t()],
          optional(:default) => term(),
          optional(:format) => Regex.t()
        }

  @type schema :: [field_def()]
  @type error_entry :: {pos_integer(), String.t(), String.t()}

  @doc """
  Reads the CSV file at `file_path` and validates every data row against `schema`.

  Returns `{:ok, valid_rows, error_report}`, `{:error, :file_not_found}` when the path does
  not exist, or `{:error, :empty_file}` when the file is zero bytes.
  """
  @spec load_file(Path.t(), schema()) ::
          {:ok, [map()], [error_entry()]} | {:error, :file_not_found | :empty_file}
  def load_file(file_path, schema) when is_binary(file_path) and is_list(schema) do
    case File.read(file_path) do
      {:ok, ""} -> {:error, :empty_file}
      {:ok, contents} -> load_string(contents, schema)
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, _reason} -> {:error, :file_not_found}
    end
  end

  @doc """
  Validates the CSV content in `csv_string` against `schema`.

  Behaves exactly like `load_file/2` but takes the CSV content directly. Returns
  `{:ok, valid_rows, error_report}`, or `{:error, :empty_file}` when the string is empty.
  """
  @spec load_string(binary(), schema()) :: {:ok, [map()], [error_entry()]} | {:error, :empty_file}
  def load_string(csv_string, schema) when is_binary(csv_string) and is_list(schema) do
    case strip_bom(csv_string) do
      "" -> {:error, :empty_file}
      contents -> parse_and_validate(contents, schema)
    end
  end

  # -- parsing ---------------------------------------------------------------------------

  @spec parse_and_validate(binary(), schema()) :: {:ok, [map()], [error_entry()]}
  defp parse_and_validate(contents, schema) do
    case CsvLoader.Parser.parse_string(contents, skip_headers: false) do
      [] ->
        {:ok, [], []}

      [header | data_rows] ->
        headers = Enum.map(header, &String.trim/1)
        indexes = header_indexes(headers)

        {rows, errors} =
          data_rows
          |> Enum.with_index(1)
          |> Enum.reduce({[], []}, fn {row, row_number}, {rows, errors} ->
            case validate_row(row, row_number, indexes, schema) do
              {:ok, map} -> {[map | rows], errors}
              {:error, row_errors} -> {rows, Enum.reverse(row_errors) ++ errors}
            end
          end)

        {:ok, Enum.reverse(rows), Enum.reverse(errors)}
    end
  end

  @spec strip_bom(binary()) :: binary()
  defp strip_bom(@bom <> rest), do: rest
  defp strip_bom(contents), do: contents

  @spec header_indexes([String.t()]) :: %{optional(String.t()) => non_neg_integer()}
  defp header_indexes(headers) do
    headers
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {name, index}, acc -> Map.put_new(acc, name, index) end)
  end

  # -- row validation --------------------------------------------------------------------

  @spec validate_row([String.t()], pos_integer(), map(), schema()) ::
          {:ok, map()} | {:error, [error_entry()]}
  defp validate_row(row, row_number, indexes, schema) do
    cells = List.to_tuple(row)

    {values, errors} =
      Enum.reduce(schema, {%{}, []}, fn field, {values, errors} ->
        raw = fetch_cell(cells, Map.get(indexes, field.name))

        case validate_field(field, raw) do
          {:ok, value} -> {Map.put(values, field_key(field), value), errors}
          {:error, messages} -> {values, errors ++ field_errors(field, row_number, messages)}
        end
      end)

    if errors == [], do: {:ok, values}, else: {:error, errors}
  end

  @spec field_errors(field_def(), pos_integer(), [String.t()]) :: [error_entry()]
  defp field_errors(field, row_number, messages) do
    Enum.map(messages, fn message -> {row_number, field.name, message} end)
  end

  @spec fetch_cell(tuple(), non_neg_integer() | nil) :: String.t()
  defp fetch_cell(_cells, nil), do: ""

  defp fetch_cell(cells, index) when index < tuple_size(cells) do
    cells |> elem(index) |> String.trim()
  end

  defp fetch_cell(_cells, _index), do: ""

  @spec field_key(field_def()) :: atom()
  defp field_key(field), do: Map.get_lazy(field, :key, fn -> String.to_atom(field.name) end)

  @spec validate_field(field_def(), String.t()) :: {:ok, term()} | {:error, [String.t()]}
  defp validate_field(field, "") do
    if Map.get(field, :required, true) do
      {:error, ["is required"]}
    else
      {:ok, Map.get(field, :default, nil)}
    end
  end

  defp validate_field(field, raw) do
    format_errors = check_format(field, raw)

    case coerce(field, raw) do
      {:ok, value} when format_errors == [] -> {:ok, value}
      {:ok, _value} -> {:error, format_errors}
      {:error, message} -> {:error, format_errors ++ [message]}
    end
  end

  @spec check_format(field_def(), String.t()) :: [String.t()]
  defp check_format(field, raw) do
    case Map.get(field, :format) do
      nil -> []
      regex -> if Regex.match?(regex, raw), do: [], else: ["does not match expected format"]
    end
  end

  # -- coercion --------------------------------------------------------------------------

  @spec coerce(field_def(), String.t()) :: {:ok, term()} | {:error, String.t()}
  defp coerce(field, raw) do
    case Map.get(field, :type, :string) do
      :string -> {:ok, raw}
      :integer -> coerce_integer(raw)
      :float -> coerce_float(raw)
      :boolean -> coerce_boolean(raw)
      :date -> coerce_date(raw)
      :enum -> coerce_enum(field, raw)
    end
  end

  @spec coerce_integer(String.t()) :: {:ok, integer()} | {:error, String.t()}
  defp coerce_integer(raw) do
    {:ok, String.to_integer(raw)}
  rescue
    ArgumentError -> {:error, "must be a valid integer"}
  end

  @spec coerce_float(String.t()) :: {:ok, float()} | {:error, String.t()}
  defp coerce_float(raw) do
    {:ok, String.to_float(raw)}
  rescue
    ArgumentError ->
      case coerce_integer(raw) do
        {:ok, integer} -> {:ok, integer * 1.0}
        {:error, _message} -> {:error, "must be a valid float"}
      end
  end

  @spec coerce_boolean(String.t()) :: {:ok, boolean()} | {:error, String.t()}
  defp coerce_boolean(raw) do
    case String.downcase(raw) do
      "true" -> {:ok, true}
      "1" -> {:ok, true}
      "false" -> {:ok, false}
      "0" -> {:ok, false}
      _other -> {:error, "must be a valid boolean"}
    end
  end

  @spec coerce_date(String.t()) :: {:ok, Date.t()} | {:error, String.t()}
  defp coerce_date(raw) do
    case Date.from_iso8601(raw) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "must be a valid date"}
    end
  end

  @spec coerce_enum(field_def(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp coerce_enum(field, raw) do
    values = Map.get(field, :values, [])

    if raw in values do
      {:ok, raw}
    else
      {:error, "must be one of: " <> Enum.join(values, ", ")}
    end
  end
end