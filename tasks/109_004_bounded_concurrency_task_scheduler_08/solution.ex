  @impl true
  def init(max), do: {:ok, %{tasks: %{}, max: max}}