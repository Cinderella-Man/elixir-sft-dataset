  @spec fetch_first(
          [{term(), (-> {:ok, term()} | {:error, term()})}],
          integer(),
          non_neg_integer()
        ) :: %{term() => {:ok, term()} | {:error, term()}}