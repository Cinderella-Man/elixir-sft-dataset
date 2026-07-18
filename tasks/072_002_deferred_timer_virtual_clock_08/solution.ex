  @impl GenServer
  def init(%DateTime{} = initial), do: {:ok, %__MODULE__{time: initial}}