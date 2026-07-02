@impl true
def handle_info({:tick, name, ref}, state) do
  case Map.fetch(state, name) do
    {:ok, %{ref: ^ref} = entry} ->
      safe_invoke(entry.fun, name)
      new_ref = make_ref()
      timer = Process.send_after(self(), {:tick, name, new_ref}, entry.interval_ms)
      {:noreply, Map.put(state, name, %{entry | status: :alerting, ref: new_ref, timer: timer})}

    _ ->
      # Stale timer (reset/unregistered/replaced) — ignore.
      {:noreply, state}
  end
end

def handle_info(_msg, state), do: {:noreply, state}