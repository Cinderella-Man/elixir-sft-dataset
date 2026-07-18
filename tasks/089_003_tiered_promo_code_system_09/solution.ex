  defp build_code(attrs) do
    code = Map.get(attrs, :code)
    tiers = Map.get(attrs, :tiers)

    cond do
      not is_binary(code) ->
        {:error, :invalid_code}

      not valid_tiers?(tiers) ->
        {:error, :invalid_tiers}

      true ->
        {:ok,
         %{
           code: code,
           tiers: tiers,
           max_uses: Map.get(attrs, :max_uses, nil),
           max_uses_per_user: Map.get(attrs, :max_uses_per_user, nil),
           valid_from: Map.get(attrs, :valid_from, nil),
           valid_until: Map.get(attrs, :valid_until, nil)
         }}
    end
  end