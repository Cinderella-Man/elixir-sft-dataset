  @doc """
  Returns a new, empty `MutableDAG`.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}