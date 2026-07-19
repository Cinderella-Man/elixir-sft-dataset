  @spec register(
          term(),
          pid(),
          non_neg_integer(),
          pos_integer(),
          (term(), pos_integer() -> any())
        ) ::
          :ok