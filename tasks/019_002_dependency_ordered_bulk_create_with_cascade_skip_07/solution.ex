  @doc "Return the number of stored items."
  @spec count() :: non_neg_integer()
  def count, do: Agent.get(__MODULE__, fn %{items: items} -> map_size(items) end)