  @spec status(GenServer.server(), term()) ::
          {:ok, :pending | :completed | :dead, non_neg_integer()}