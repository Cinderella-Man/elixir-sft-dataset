  @impl GenServer
  def init(:ok), do: {:ok, %{streams: %{}}}