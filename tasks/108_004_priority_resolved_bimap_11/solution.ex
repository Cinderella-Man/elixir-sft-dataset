  @impl true
  def init(:ok) do
    # forward: key => value, reverse: value => key, prio: key => priority
    {:ok, %{forward: %{}, reverse: %{}, prio: %{}}}
  end