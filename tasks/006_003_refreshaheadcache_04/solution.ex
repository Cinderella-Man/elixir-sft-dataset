@impl true
def handle_info({:refresh_complete, key, task_ref, new_value}, state) do
  case {Map.fetch(state.entries, key), Map.fetch(state.in_flight, key)} do
    {{:ok, entry}, {:ok, ^task_ref}} ->
      now = state.clock.()
      updated = %{entry | value: new_value, expires_at: now + entry.ttl_ms}

      {:noreply,
       %{
         state
         | entries: Map.put(state.entries, key, updated),
           in_flight: Map.delete(state.in_flight, key)
       }}

    _ ->
      # Key gone, overwritten, or a newer refresh is in flight — discard.
      new_in_flight =
        case Map.fetch(state.in_flight, key) do
          {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
          _ -> state.in_flight
        end

      {:noreply, %{state | in_flight: new_in_flight}}
  end
end

def handle_info({:refresh_failed, key, task_ref, _reason}, state) do
  # Leave the old value in place; just clear the in-flight marker if still ours.
  new_in_flight =
    case Map.fetch(state.in_flight, key) do
      {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
      _ -> state.in_flight
    end

  {:noreply, %{state | in_flight: new_in_flight}}
end

def handle_info(:sweep, state) do
  now = state.clock.()

  pruned =
    state.entries
    |> Enum.reject(fn {_k, %{expires_at: e}} -> now >= e end)
    |> Map.new()

  new_in_flight =
    state.in_flight
    |> Enum.filter(fn {k, _ref} -> Map.has_key?(pruned, k) end)
    |> Map.new()

  schedule_sweep(state.sweep_interval_ms)

  {:noreply, %{state | entries: pruned, in_flight: new_in_flight}}
end

def handle_info(_msg, state), do: {:noreply, state}