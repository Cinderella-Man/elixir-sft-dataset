  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()} | {:error, :not_ready, non_neg_integer()}