  @spec get(GenServer.server(), term()) ::
          {:ok, term(), :fresh} | {:ok, term(), :stale} | :miss