  @spec drain(GenServer.server(), term(), (term() -> term()), non_neg_integer()) ::
          {:ok, %{succeeded: non_neg_integer(), failed: non_neg_integer(), processed: [term()]}}