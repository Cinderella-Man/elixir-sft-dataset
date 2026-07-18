  @spec parse_line(String.t()) :: {:ok, map()} | :skip
  defp parse_line(line) do
    case Jason.decode(line) do
      {:ok, value} when is_map(value) ->
        {:ok, value}

      {:ok, _non_map} ->
        Logger.warning("[JsonlIngestion] Line is valid JSON but not an object, skipping")
        :skip

      {:error, reason} ->
        Logger.warning("[JsonlIngestion] Malformed JSON line, skipping: #{inspect(reason)}")
        :skip
    end
  end