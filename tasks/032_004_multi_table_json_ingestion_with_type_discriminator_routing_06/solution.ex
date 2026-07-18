  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        Logger.error("[Ingestion] cannot read #{inspect(path)}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
  end