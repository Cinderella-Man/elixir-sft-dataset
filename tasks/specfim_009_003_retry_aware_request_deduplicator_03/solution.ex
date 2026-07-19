  @spec execute(GenServer.server(), term(), (-> term()), keyword()) ::
          {:ok, term()} | {:error, term()}