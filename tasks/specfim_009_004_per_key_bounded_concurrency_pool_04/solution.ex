  @spec status(GenServer.server(), term()) :: %{
          running: non_neg_integer(),
          queued: non_neg_integer()
        }