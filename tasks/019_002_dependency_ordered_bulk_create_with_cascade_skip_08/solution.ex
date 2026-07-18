  @doc "Fetch a stored item by id, or `nil` if it does not exist."
  @spec get(integer()) :: item() | nil
  def get(id), do: Agent.get(__MODULE__, fn %{items: items} -> Map.get(items, id) end)