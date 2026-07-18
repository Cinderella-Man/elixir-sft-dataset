  @spec check_file(String.t()) :: :ok | {:error, :file_not_found | :empty_file}
  defp check_file(path) do
    cond do
      not File.exists?(path) ->
        Logger.error("[CsvIngestion] File not found: #{inspect(path)}")
        {:error, :file_not_found}

      File.stat!(path).size == 0 ->
        Logger.error("[CsvIngestion] File is empty: #{inspect(path)}")
        {:error, :empty_file}

      true ->
        :ok
    end
  end