@impl true
def handle_call({:pending, key}, _from, state) do
  count =
    case Map.get(state, key) do
      %{items: items} -> length(items)
      nil -> 0
    end

  {:reply, count, state}
end