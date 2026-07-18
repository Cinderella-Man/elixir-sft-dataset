  @spec new(t(), map()) :: map()
  def new(%__MODULE__{initial: initial}, attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, initial)
  end