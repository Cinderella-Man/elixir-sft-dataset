  @spec status(GenServer.server(), term()) ::
          :idle | {:retrying, pos_integer(), non_neg_integer()}