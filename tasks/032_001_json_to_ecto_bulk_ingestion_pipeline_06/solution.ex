  @spec read_file(file_path()) :: {:ok, binary()} | {:error, :file_not_found}
  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        Logger.error("[DataIngestion] Could not read file #{inspect(path)}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
  end