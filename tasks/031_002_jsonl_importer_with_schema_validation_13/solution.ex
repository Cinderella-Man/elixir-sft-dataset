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