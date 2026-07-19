  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()}