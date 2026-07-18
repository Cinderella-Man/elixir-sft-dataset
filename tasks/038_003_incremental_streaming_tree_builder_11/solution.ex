  @impl true
  def init(strategy) do
    {:ok, %{items: [], ids: MapSet.new(), strategy: strategy}}
  end