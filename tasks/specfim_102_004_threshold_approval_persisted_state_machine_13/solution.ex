  @spec transition(server(), String.t(), event()) ::
          {:ok, state_name(), non_neg_integer()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}