  @doc "Discards the pending func for `key` without running it."
  @spec cancel(term()) :: :ok
  def cancel(key), do: GenServer.call(__MODULE__, {:cancel, key})