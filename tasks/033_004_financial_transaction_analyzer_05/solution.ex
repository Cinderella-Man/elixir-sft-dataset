  @doc "Analyzes the transaction log at `path`. Returns `{:ok, stats}` or `{:error, reason}`."
  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) do
    case File.open(path, [:read]) do
      {:error, reason} ->
        {:error, reason}

      {:ok, device} ->
        :ok = File.close(device)
        stream_report(path)
    end
  end