@impl true
def handle_call({:check, key, max_requests, window_ms}, _from, state) do
  now = state.clock.()

  # Snap `now` into the absolute window it belongs to.
  window_index = div(now, window_ms)
  window_end = (window_index + 1) * window_ms
  counter_key = {key, window_index}

  count = Map.get(state.counters, counter_key, {0, window_end}) |> elem(0)

  if count < max_requests do
    new_count = count + 1
    remaining = max_requests - new_count
    new_counters = Map.put(state.counters, counter_key, {new_count, window_end})

    {:reply, {:ok, remaining}, %{state | counters: new_counters}}
  else
    # Counter saturated; wait until this window ends.
    retry_after = max(window_end - now, 1)
    {:reply, {:error, :rate_limited, retry_after}, state}
  end
end
