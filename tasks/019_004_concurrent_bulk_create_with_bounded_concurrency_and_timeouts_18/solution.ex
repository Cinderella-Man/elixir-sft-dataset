  @doc """
  Fetch a stored item by `id`, or `nil` when absent.
  """
  @spec get(pos_integer()) :: item() | nil
  def get(id), do: Agent.get(__MODULE__, fn %{items: items} -> Map.get(items, id) end)