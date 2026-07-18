  @spec can?(map(), atom()) :: boolean()
  def can?(record, event) do
    match?({:ok, _}, transition(record, event))
  end