  @spec rank(board(), player_id(), integer()) ::
          {:ok, pos_integer(), number()} | {:error, :not_found}