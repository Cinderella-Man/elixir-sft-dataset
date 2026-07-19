  @spec check(GenServer.server(), term(), [{atom(), pos_integer(), pos_integer()}, ...]) ::
          {:ok, %{atom() => non_neg_integer()}}
          | {:error, :rate_limited, atom(), non_neg_integer()}