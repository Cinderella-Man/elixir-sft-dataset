  @impl true
  @spec init(:ok) :: {:ok, state}
  def init(:ok) do
    {:ok, %{objects: %{}, branches: %{}}}
  end