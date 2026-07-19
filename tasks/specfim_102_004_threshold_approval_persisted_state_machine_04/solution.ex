  @spec get_state(server(), String.t()) ::
          {:ok, state_name(), non_neg_integer()} | {:error, :not_found}