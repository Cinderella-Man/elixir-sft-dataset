  @impl true
  def init(:ok) do
    # forward: key => value, reverse: value => key
    {:ok, %{forward: %{}, reverse: %{}}}
  end