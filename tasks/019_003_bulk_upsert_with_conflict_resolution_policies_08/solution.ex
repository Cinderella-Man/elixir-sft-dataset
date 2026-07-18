  @doc "Fetch a record by `sku`, or `nil` if absent."
  @spec get(String.t()) :: record_t | nil
  def get(sku), do: Agent.get(__MODULE__, fn %{records: r} -> Map.get(r, sku) end)