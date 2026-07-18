  @impl GenServer
  @spec init(:ok) :: {:ok, state()}
  def init(:ok) do
    {:ok, %{nodes: %{}, next_id: 1}}
  end