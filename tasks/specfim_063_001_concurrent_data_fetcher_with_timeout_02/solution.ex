  @spec fetch_all([{term(), (-> {:ok, term()} | {:error, term()})}, ...], non_neg_integer()) ::
          %{term() => {:ok, term()} | {:error, term()}}