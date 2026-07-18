  @spec validate_list(term()) :: {:ok, list()} | {:error, :not_a_list}
  defp validate_list(value) when is_list(value), do: {:ok, value}

  defp validate_list(value) do
    Logger.error("[DataIngestion] Expected a JSON array, got: #{inspect(value, limit: 5)}")
    {:error, :not_a_list}
  end