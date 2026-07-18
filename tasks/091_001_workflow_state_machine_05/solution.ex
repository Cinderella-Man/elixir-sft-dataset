  @doc """
  Build a new record.

  Returns `attrs` merged with `%{state: :draft}`. Any `:state` provided in
  `attrs` is overridden — a new record always starts in `:draft`.
  """
  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, :draft)
  end