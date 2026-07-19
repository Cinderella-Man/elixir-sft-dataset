  @spec acquire(GenServer.server(), term(), number(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_exceeded, pos_integer()}