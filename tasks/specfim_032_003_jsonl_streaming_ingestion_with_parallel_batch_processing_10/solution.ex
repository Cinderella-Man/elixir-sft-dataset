  @spec try_insert_batch(repo(), schema(), [map()], map()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer()}