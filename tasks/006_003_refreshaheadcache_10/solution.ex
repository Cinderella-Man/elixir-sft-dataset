  @impl true
  def handle_call({:put, key, value, ttl_ms, loader}, _from, state) do
    now = state.clock.()

    entry = %{
      value: value,
      expires_at: now + ttl_ms,
      ttl_ms: ttl_ms,
      loader: loader
    }

    # Invalidate any in-flight refresh for this key so a stale result can't
    # clobber the new put.
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
          now >= entry.expires_at ->
            new_in_flight = Map.delete(state.in_flight, key)

            {:reply, :miss,
             %{
               state
               | entries: Map.delete(state.entries, key),
                 in_flight: new_in_flight
             }}

          # Past refresh threshold — trigger an async refresh if none running.
          should_refresh?(entry, now, state.refresh_threshold) and
              not Map.has_key?(state.in_flight, key) ->
            task_ref = spawn_refresh(key, entry.loader)
            new_in_flight = Map.put(state.in_flight, key, task_ref)
            {:reply, {:ok, entry.value}, %{state | in_flight: new_in_flight}}

          # Fresh enough OR refresh already in flight — just return value.
          true ->
            {:reply, {:ok, entry.value}, state}
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
     %{
       entries: map_size(state.entries),
       refreshes_in_flight: map_size(state.in_flight)
     }, state}
  end