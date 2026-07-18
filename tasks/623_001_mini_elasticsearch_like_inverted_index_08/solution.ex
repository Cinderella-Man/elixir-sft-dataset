  @spec search(GenServer.server(), String.t(), keyword()) :: [%{id: term(), score: float()}]
  @doc "Search the index. Returns `[%{id: id, score: score}, ...]` sorted by score descending."
  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end