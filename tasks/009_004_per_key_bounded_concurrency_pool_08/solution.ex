  @impl GenServer
  def init(config) do
    {:ok, Map.put(config, :keys, %{})}
  end