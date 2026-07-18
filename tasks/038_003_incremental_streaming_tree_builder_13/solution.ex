  defp put_item(state, item, id) do
    %{state | items: [item | state.items], ids: MapSet.put(state.ids, id)}
  end