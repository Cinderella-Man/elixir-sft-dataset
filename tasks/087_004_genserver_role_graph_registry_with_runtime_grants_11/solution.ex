  @impl true
  def init(:ok) do
    {:ok, %{roles: MapSet.new(), inherits: %{}, grants: %{}}}
  end