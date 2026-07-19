  @spec transition(GenServer.server(), String.t(), event()) ::
          {:ok, state()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}