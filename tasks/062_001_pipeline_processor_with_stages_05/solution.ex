  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}