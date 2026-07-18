  @impl true
  def init(:ok), do: {:ok, %{tree: nil, next_id: 1, entries: %{}}}