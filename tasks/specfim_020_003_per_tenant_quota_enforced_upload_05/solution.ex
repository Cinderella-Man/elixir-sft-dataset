  @spec delete(GenServer.server(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :forbidden} | {:error, :not_found}