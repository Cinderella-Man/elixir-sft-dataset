  @spec subscribe(GenServer.server(), String.t(), pid(), list()) ::
          {:ok, reference()} | {:error, :invalid_filter}