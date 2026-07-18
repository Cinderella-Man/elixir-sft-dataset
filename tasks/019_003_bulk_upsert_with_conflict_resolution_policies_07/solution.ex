  @doc "Return the number of stored records."
  @spec count() :: non_neg_integer
  def count, do: Agent.get(__MODULE__, fn %{records: r} -> map_size(r) end)