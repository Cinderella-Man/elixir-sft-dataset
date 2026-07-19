  @spec inspect_token(token()) ::
          {:ok, %{identifier: binary(), caveats: [caveat()]}} | {:error, :malformed}