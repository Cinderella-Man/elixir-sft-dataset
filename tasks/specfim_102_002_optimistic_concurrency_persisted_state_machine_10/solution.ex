  @spec persist(module(), String.t(), event(), state_name(), state_name(), non_neg_integer()) ::
          {:ok, EntityTransition.t()} | {:error, term()}