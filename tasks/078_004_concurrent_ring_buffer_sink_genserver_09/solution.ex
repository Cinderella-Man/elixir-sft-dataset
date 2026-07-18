  @doc "Returns `{:ok, item}` for the oldest item, or `:error` if empty."
  @spec peek_oldest(GenServer.server()) :: {:ok, any()} | :error
  def peek_oldest(server), do: GenServer.call(server, :peek_oldest)