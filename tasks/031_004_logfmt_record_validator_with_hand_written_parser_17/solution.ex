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