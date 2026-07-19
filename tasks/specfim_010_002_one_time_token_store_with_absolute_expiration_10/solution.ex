  @spec fetch_live_token(%{token_id() => token()}, token_id(), integer()) ::
          {:ok, token()} | :expired | :missing