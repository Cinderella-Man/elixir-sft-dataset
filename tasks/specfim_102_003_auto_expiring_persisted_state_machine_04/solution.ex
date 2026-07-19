  @spec get_state(GenServer.server(), String.t()) ::
          {:ok, state()} | {:error, :not_found}