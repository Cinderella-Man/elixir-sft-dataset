  defp fetch_live_token(tokens, token_id, now) do
    case Map.fetch(tokens, token_id) do
      {:ok, token} ->
        if expired?(token, now), do: :expired, else: {:ok, token}

      :error ->
        :missing
    end
  end