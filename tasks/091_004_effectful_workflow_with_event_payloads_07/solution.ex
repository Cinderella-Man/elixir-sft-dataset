  @spec can?(map(), atom(), map()) :: boolean()
  def can?(record, event, payload \\ %{}) do
    match?({:ok, _}, transition(record, event, payload))
  end