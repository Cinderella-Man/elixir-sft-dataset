  @doc "Return every stored item."
  @spec all() :: [item()]
  def all, do: Agent.get(__MODULE__, fn %{items: items} -> Map.values(items) end)