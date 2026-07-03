  defp evict_lru(state) do
    {lru_key, _} =
      Enum.min_by(state.idempotency_keys, fn {_key, {_result, tick}} -> tick end)

    %{state | idempotency_keys: Map.delete(state.idempotency_keys, lru_key)}
  end