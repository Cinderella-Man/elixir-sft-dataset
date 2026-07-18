  @spec remove(GenServer.server(), term()) :: :ok
  @doc "Remove a document from the index. No-op when `id` is absent."
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end