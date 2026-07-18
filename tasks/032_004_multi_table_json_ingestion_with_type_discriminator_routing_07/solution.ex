  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("[MultiSchemaIngestion] JSON parse error: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end