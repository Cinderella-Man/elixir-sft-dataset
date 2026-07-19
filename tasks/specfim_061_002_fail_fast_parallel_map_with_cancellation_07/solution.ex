  @spec pmap(Enumerable.t(), (term() -> term()), pos_integer()) ::
          {:ok, [term()]} | {:error, {non_neg_integer(), term()}}