@impl true
def handle_info(:cleanup, state) do
  now = state.clock.()

  cleaned =
    state.keys
    |> Enum.reject(fn {_key, entry} -> removable?(entry, now) end)
    |> Map.new()

  schedule_cleanup(state.cleanup_interval_ms)

  {:noreply, %{state | keys: cleaned}}
end
