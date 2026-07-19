  @spec open(token(), binary(), keyword()) ::
          {:ok, term()} | {:error, :expired | :invalid | :malformed}