def handle_call({:put, key, value, fresh_ms, stale_ms, loader}, _from, state) do
  now = state.clock.()

  entry = %{
    value: value,
    fresh_until: now + fresh_ms,
    hard_expires_at: now + fresh_ms + stale_ms,
    fresh_ms: fresh_ms,
    stale_ms: stale_ms,
    loader: loader
  }

  # Invalidate any in-flight revalidation so a stale result can't clobber.
  new_in_flight = Map.delete(state.in_flight, key)

  {:reply, :ok,
   %{state | entries: Map.put(state.entries, key, entry), in_flight: new_in_flight}}
end

def handle_call({:get, key}, _from, state) do
  now = state.clock.()

  case Map.fetch(state.entries, key) do
    {:ok, entry} ->
      cond do
        # Hard expiry — evict lazily and miss.
        now >= entry.hard_expires_at ->
          {:reply, :miss,
           %{
             state
             | entries: Map.delete(state.entries, key),
               in_flight: Map.delete(state.in_flight, key)
           }}

        # Still fresh — serve directly, no revalidation.
        now < entry.fresh_until ->
          {:reply, {:ok, entry.value, :fresh}, state}

        # Stale window — serve stale, trigger revalidation if not in flight.
        true ->
          new_state =
            if Map.has_key?(state.in_flight, key) do
              state
            else
              task_ref = spawn_revalidate(key, entry.loader)
              %{state | in_flight: Map.put(state.in_flight, key, task_ref)}
            end

          {:reply, {:ok, entry.value, :stale}, new_state}
      end

    :error ->
      {:reply, :miss, state}
  end
end

def handle_call({:delete, key}, _from, state) do
  {:reply, :ok,
   %{
     state
     | entries: Map.delete(state.entries, key),
       in_flight: Map.delete(state.in_flight, key)
   }}
end

def handle_call(:stats, _from, state) do
  {:reply,
   %{entries: map_size(state.entries), revalidations_in_flight: map_size(state.in_flight)},
   state}
end