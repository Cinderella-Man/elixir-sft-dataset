defmodule CsvLoader do
  @moduledoc """
  Reads CSV data (from a file or string), validates each row against a provided
  schema, coerces values to their declared Elixir types, and returns structured
  results splitting valid rows from errors.

  ## Schema

  A schema is a list of field definition maps:

      [
        %{name: "email", type: :string, format: ~r/@/},
        %{name: "age",   type: :integer},
        %{name: "score", type: :float, required: false, default: 0.0},
        %{name: "active", type: :boolean},
        %{name: "joined", type: :date},
        %{name: "role", type: :enum, values: ["admin", "user", "guest"]}
      ]

  Valid rows are returned as maps with atom keys and typed Elixir values.
  """

  # ---------------------------------------------------------------------------
  # CSV parser definition (NimbleCSV)
  # ---------------------------------------------------------------------------
  NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\"")

  # Accepted boolean literals (lowercased for comparison).
  @true_values ~w(true 1)
  @false_values ~w(false 0)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Loads the CSV file at `file_path` and validates/coerces it against `schema`.

  Returns `{:ok, valid_rows, error_report}`, `{:error, :file_not_found}` when the
  path does not exist, or `{:error, :empty_file}` when the file has no content.
  """
  @spec load_file(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :file_not_found | :empty_file}
  def load_file(file_path, schema) do
    case File.read(file_path) do
      {:ok, ""} ->
        {:error, :empty_file}

      {:ok, contents} ->
        load_string(contents, schema)

      {:error, :enoent} ->
        {:error, :file_not_found}
    end
  end

  @doc """
  Same as `load_file/2` but takes the CSV content as a binary string.

  Returns `{:ok, valid_rows, error_report}` or `{:error, :empty_file}`.
  """
  @spec load_string(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :empty_file}
  def load_string(csv_string, schema) do
    stripped = strip_bom(csv_string)

    if String.trim(stripped) == "" do
      {:error, :empty_file}
    else
      stripped
      |> parse_csv()
      |> process_parsed(schema)
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(other), do: other

  defp parse_csv(text) do
    case CsvLoader.Parser.parse_string(text, skip_headers: false) do
      [] ->
        {[], []}

      [headers | rows] ->
        trimmed_headers = Enum.map(headers, &String.trim/1)
        {trimmed_headers, rows}
    end
  end

  defp process_parsed({_headers, []}, _schema), do: {:ok, [], []}

  defp process_parsed({headers, rows}, schema) do
    header_count = length(headers)

    {valid_rows, error_report} =
      rows
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {raw_row, row_num}, {valid_acc, err_acc} ->
        row_map = build_row_map(headers, raw_row, header_count)
        {errors, coerced} = validate_and_coerce_row(row_map, schema, headers)

        case errors do
          [] ->
            {[coerced | valid_acc], err_acc}

          _ ->
            tagged = Enum.map(errors, fn {field, msg} -> {row_num, field, msg} end)
            {valid_acc, err_acc ++ tagged}
        end
      end)

    {:ok, Enum.reverse(valid_rows), error_report}
  end

  defp build_row_map(headers, raw_row, header_count) do
    padded =
      if length(raw_row) < header_count do
        raw_row ++ List.duplicate("", header_count - length(raw_row))
      else
        Enum.take(raw_row, header_count)
      end

    headers
    |> Enum.zip(padded)
    |> Map.new(fn {h, v} -> {h, String.trim(v)} end)
  end

  # Validate and coerce a single row.
  # Returns {errors, coerced_map}.
  # coerced_map is only meaningful when errors is empty.
  defp validate_and_coerce_row(row_map, schema, headers) do
    Enum.reduce(schema, {[], %{}}, fn field, {errs, coerced} ->
      if field.name in headers do
        apply_field(row_map, field, errs, coerced)
      else
        missing_column(field, errs, coerced)
      end
    end)
  end

  # A schema field whose column is absent from the header: report a "is required"
  # error when required, otherwise omit the key from the coerced row entirely.
  defp missing_column(field, errs, coerced) do
    if Map.get(field, :required, true) do
      {errs ++ [{field.name, "is required"}], coerced}
    else
      {errs, coerced}
    end
  end

  defp apply_field(row_map, field, errs, coerced) do
    value = Map.get(row_map, field.name, "")
    key = Map.get(field, :key, String.to_atom(field.name))

    case validate_and_coerce_field(value, field) do
      {:ok, coerced_value} ->
        {errs, Map.put(coerced, key, coerced_value)}

      {:errors, field_errors} ->
        {errs ++ field_errors, coerced}
    end
  end

  defp validate_and_coerce_field(value, field) do
    required? = Map.get(field, :required, true)
    type = Map.get(field, :type, :string)
    format = Map.get(field, :format, nil)
    default = Map.get(field, :default, nil)
    empty? = value == ""

    cond do
      empty? and not required? ->
        {:ok, default}

      empty? ->
        # Required and empty — report error, skip format/type checks.
        {:errors, [{field.name, "is required"}]}

      true ->
        non_empty_errors(value, field, type, format)
    end
  end

  defp non_empty_errors(value, field, type, format) do
    format_errors =
      if format != nil do
        check_format(value, format, field.name)
      else
        []
      end

    {type_errors, coerced_value} = coerce_type(value, type, field)
    all_errors = format_errors ++ type_errors

    if all_errors == [] do
      {:ok, coerced_value}
    else
      {:errors, all_errors}
    end
  end

  # Type coercion — returns {errors, coerced_value}.
  # coerced_value is only meaningful when errors is [].

  defp coerce_type(value, :string, _field), do: {[], value}

  defp coerce_type(value, :integer, field) do
    case Integer.parse(value) do
      {int, ""} -> {[], int}
      _ -> {[{field.name, "must be a valid integer"}], nil}
    end
  end

  defp coerce_type(value, :float, field) do
    cond do
      match?({_f, ""}, Float.parse(value)) ->
        {f, ""} = Float.parse(value)
        {[], f}

      match?({_i, ""}, Integer.parse(value)) ->
        {i, ""} = Integer.parse(value)
        {[], i * 1.0}

      true ->
        {[{field.name, "must be a valid float"}], nil}
    end
  end

  defp coerce_type(value, :boolean, field) do
    lower = String.downcase(value)

    cond do
      lower in @true_values -> {[], true}
      lower in @false_values -> {[], false}
      true -> {[{field.name, "must be a valid boolean"}], nil}
    end
  end

  defp coerce_type(value, :date, field) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {[], date}
      {:error, _} -> {[{field.name, "must be a valid date"}], nil}
    end
  end

  defp coerce_type(value, :enum, field) do
    allowed = Map.fetch!(field, :values)

    if value in allowed do
      {[], value}
    else
      msg = "must be one of: #{Enum.join(allowed, ", ")}"
      {[{field.name, msg}], nil}
    end
  end

  # Format checker ------------------------------------------------------

  defp check_format(value, %Regex{} = regex, name) do
    if Regex.match?(regex, value) do
      []
    else
      [{name, "does not match expected format"}]
    end
  end
end
