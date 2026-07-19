  @spec stats(GenServer.server()) :: %{
          entries: non_neg_integer(),
          refreshes_in_flight: non_neg_integer()
        }