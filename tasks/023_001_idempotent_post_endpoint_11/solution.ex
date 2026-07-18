  defp maybe_cache(state, nil, _result, _now), do: state

  defp maybe_cache(state, key, result, now) do
    expiry = now + state.ttl_ms
    %{state | idempotency_keys: Map.put(state.idempotency_keys, key, {result, expiry})}
  end