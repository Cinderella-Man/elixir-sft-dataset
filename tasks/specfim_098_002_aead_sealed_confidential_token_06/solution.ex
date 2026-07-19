  @spec decrypt_and_validate(
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, term()} | {:error, :expired | :invalid | :malformed}