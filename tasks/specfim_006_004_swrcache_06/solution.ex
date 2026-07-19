  @spec stats(GenServer.server()) ::
          %{entries: non_neg_integer(), revalidations_in_flight: non_neg_integer()}