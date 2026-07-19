  @spec jobs(GenServer.server()) ::
          [{term(), :pending | :completed | :dead, NaiveDateTime.t(), non_neg_integer()}]