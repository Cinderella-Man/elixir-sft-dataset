  @impl true
  def init(_opts) do
    {:ok, %{topics: %{}, monitors: %{}}}
  end