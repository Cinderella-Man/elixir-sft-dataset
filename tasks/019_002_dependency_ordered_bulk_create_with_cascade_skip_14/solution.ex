  defp insert(name, ref, parent_id) do
    Agent.get_and_update(__MODULE__, fn %{items: items, next_id: id} = st ->
      item = %{id: id, name: name, ref: ref, parent_id: parent_id}
      {item, %{st | items: Map.put(items, id, item), next_id: id + 1}}
    end)
  end