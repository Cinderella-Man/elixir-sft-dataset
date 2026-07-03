defp cached(_state, nil, _now), do: :miss

defp cached(state, key, now) do
  case Map.get(state.idempotency_keys, key) do
    {response, expiry} when expiry > now -> {:hit, response}
    _ -> :miss
  end
end