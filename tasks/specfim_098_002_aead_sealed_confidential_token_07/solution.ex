  @spec validate_and_deserialize(binary(), non_neg_integer(), keyword()) ::
          {:ok, term()} | {:error, :expired | :malformed}