  @doc false
  @impl true
  @spec init(:ok) :: {:ok, t()}
  def init(:ok), do: {:ok, %__MODULE__{}}