  @spec acquire_lease(
          GenServer.server(),
          term(),
          pos_integer(),
          number(),
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, reference(), non_neg_integer()}