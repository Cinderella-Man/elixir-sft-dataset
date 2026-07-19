  @spec save(GenServer.server(), String.t(), map()) ::
          {:ok, map(), map()} | {:error, :quota_exceeded, map()}