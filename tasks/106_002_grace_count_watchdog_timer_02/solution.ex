  @impl true
  def handle_info({:tick, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        misses = entry.misses + 1

        if misses >= entry.max_misses do
          safe_invoke(entry.fun, name, misses)
          {:noreply, Map.delete(state, name)}
        else
          new_ref = make_ref()
          timer = Process.send_after(self(), {:tick, name, new_ref}, entry.interval_ms)
          {:noreply, Map.put(state, name, %{entry | misses: misses, ref: new_ref, timer: timer})}
        end

      _ ->
        # Stale timer (reset/unregistered/replaced) — ignore.
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}