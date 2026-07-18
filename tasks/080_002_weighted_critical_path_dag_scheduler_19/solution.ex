  @doc """
  Returns a new, empty weighted DAG with no tasks and no dependencies.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{durations: %{}, out_edges: %{}, in_edges: %{}}
  end