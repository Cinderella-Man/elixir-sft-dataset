  @spec parse_json(binary()) :: {:ok, term()} | {:error, :invalid_json}
  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("[DataIngestion] JSON parse error: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end