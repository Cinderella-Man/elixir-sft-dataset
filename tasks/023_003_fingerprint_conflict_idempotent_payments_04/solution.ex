@impl true
def handle_info(:cleanup, state) do
  now = state.clock.()

  kept =
    state.idempotency_keys
    |> Enum.filter(fn {_key, {_result, _fp, expiry}} -> expiry > now end)
    |> Map.new()

  schedule_cleanup(state.cleanup_interval_ms)
  {:noreply, %{state | idempotency_keys: kept}}
end

def handle_info(_msg, state), do: {:noreply, state}