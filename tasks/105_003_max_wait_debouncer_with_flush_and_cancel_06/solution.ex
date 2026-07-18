  @doc "Immediately runs the pending func for `key` (if any) and clears state."
  @spec flush(term()) :: :ok
  def flush(key), do: GenServer.call(__MODULE__, {:flush, key})