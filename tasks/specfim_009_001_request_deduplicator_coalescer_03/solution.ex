  @spec execute(GenServer.server(), term(), (-> term())) ::
          {:ok, term()} | {:error, term()}