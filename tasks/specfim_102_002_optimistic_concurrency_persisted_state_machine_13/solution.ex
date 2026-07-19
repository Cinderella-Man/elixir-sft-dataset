  @spec transition(GenServer.server(), String.t(), event(), non_neg_integer()) ::
          {:ok, state_name(), non_neg_integer()}
          | {:error, :not_found}
          | {:error, {:stale_version, non_neg_integer()}}
          | {:error, :invalid_transition}
          | {:error, {:db_error, term()}}