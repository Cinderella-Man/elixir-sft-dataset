  @doc "Returns `{:ok, item}` for the newest item, or `:error` if empty."
  @spec peek_newest(GenServer.server()) :: {:ok, any()} | :error
  def peek_newest(server), do: GenServer.call(server, :peek_newest)