defp cancel_entry(state, name) do
  case Map.fetch(state, name) do
    {:ok, entry} ->
      disarm(entry)
      Map.delete(state, name)

    :error ->
      state
  end
end