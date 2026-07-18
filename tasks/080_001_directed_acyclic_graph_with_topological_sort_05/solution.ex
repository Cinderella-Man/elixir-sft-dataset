  @doc "Returns an empty DAG."
  @spec new() :: t()
  def new do
    %__MODULE__{
      vertices: MapSet.new(),
      out_edges: %{},
      in_edges: %{}
    }
  end