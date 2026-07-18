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