  @doc "Return all stored records."
  @spec all() :: [record_t]
  def all, do: Agent.get(__MODULE__, fn %{records: r} -> Map.values(r) end)