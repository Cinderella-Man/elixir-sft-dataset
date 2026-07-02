defp cancel_entry(state, name) do
  case Map.fetch(state, name) do
    {:ok, entry} ->
      _ = Process.cancel_timer(entry.timer_ref)
      Map.delete(state, name)

    :error ->
      state
  end
end