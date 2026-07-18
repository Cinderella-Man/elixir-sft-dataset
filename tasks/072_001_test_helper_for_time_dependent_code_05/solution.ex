  @impl GenServer
  def init(%DateTime{} = initial), do: {:ok, initial}