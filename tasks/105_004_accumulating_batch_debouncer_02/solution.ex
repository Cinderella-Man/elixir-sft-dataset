@impl true
def handle_cast({:submit, key, delay_ms, item, handler}, state) do
  # Items are stored reversed (newest first) and reversed at flush time so we
  # never pay O(n) per append.
  items =
    case Map.get(state, key) do
      %{timer: ref, items: items} ->
        Process.cancel_timer(ref)
        [item | items]

      nil ->
        [item]
    end

  ref = Process.send_after(self(), {:flush, key}, delay_ms)
  entry = %{timer: ref, items: items, handler: handler}
  {:noreply, Map.put(state, key, entry)}
end