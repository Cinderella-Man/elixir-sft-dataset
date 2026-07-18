  @doc "Builds a new effectful workflow from `attrs`. Returns the workflow map."
  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, :draft)
  end