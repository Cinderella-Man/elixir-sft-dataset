  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    {:ok, %{forward: %{}, reverse: %{}, access: %{}, clock: 0, capacity: capacity}}
  end