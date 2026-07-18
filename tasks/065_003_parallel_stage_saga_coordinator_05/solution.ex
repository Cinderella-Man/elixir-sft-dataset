  @doc "Returns a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}