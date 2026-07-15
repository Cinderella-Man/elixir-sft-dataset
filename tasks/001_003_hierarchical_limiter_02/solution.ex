@impl true
def handle_call({:check, key, tiers}, _from, state) do
  now = state.clock.()
  widest_window = tiers |> Enum.map(fn {_n, _m, w} -> w end) |> Enum.max()

  # Fetch and lazily prune to the widest window ever seen for this key so a
  # narrow check can't discard timestamps a wider tier still needs.
  {timestamps, old_widest} = Map.get(state.keys, key, {[], 0})
  widest = max(old_widest, widest_window)
  active = Enum.take_while(timestamps, fn ts -> ts > now - widest end)

  # Evaluate every tier against the pruned list.
  case evaluate_tiers(tiers, active, now) do
    {:ok, remaining_by_tier} ->
      # All tiers pass — record this request's timestamp at the front.
      new_entry = {[now | active], widest}
      {:reply, {:ok, remaining_by_tier}, %{state | keys: Map.put(state.keys, key, new_entry)}}

    {:rejected, tier_name, retry_after} ->
      # Persist the pruned list even on failure so we don't re-prune next time.
      new_entry = {active, widest}

      {:reply, {:error, :rate_limited, tier_name, retry_after},
       %{state | keys: Map.put(state.keys, key, new_entry)}}
  end
end
