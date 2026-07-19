  @spec get_state(GenServer.server(), String.t()) ::
          {:ok, state_name(), non_neg_integer()} | {:error, :not_found}