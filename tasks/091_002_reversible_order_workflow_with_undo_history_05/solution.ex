  @doc "Builds a new reversible order workflow from `attrs`. Returns the workflow map."
  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    attrs
    |> Map.put(:state, :draft)
    |> Map.put(:history, [])
  end