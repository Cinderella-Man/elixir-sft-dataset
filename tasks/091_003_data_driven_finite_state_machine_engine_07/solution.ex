  @spec can?(t(), map(), atom()) :: boolean()
  def can?(%__MODULE__{} = machine, record, event) do
    match?({:ok, _}, transition(machine, record, event))
  end