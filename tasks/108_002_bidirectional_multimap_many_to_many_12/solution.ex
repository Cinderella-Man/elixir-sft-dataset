  @impl true
  def init(:ok) do
    # forward: key => MapSet of values, reverse: value => MapSet of keys
    {:ok, %{forward: %{}, reverse: %{}}}
  end