  @impl GenServer
  def init(_opts), do: {:ok, %{events: %{}}}