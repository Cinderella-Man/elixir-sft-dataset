  @doc "Cancels a pending timer. Returns `:ok` if it was pending, `:error` otherwise."
  @spec cancel(GenServer.server(), non_neg_integer()) :: :ok | :error
  def cancel(server, ref), do: GenServer.call(server, {:cancel, ref})