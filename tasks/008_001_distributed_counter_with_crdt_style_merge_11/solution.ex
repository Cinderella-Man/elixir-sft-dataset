  @impl GenServer
  def init(:ok) do
    {:ok, empty_state()}
  end