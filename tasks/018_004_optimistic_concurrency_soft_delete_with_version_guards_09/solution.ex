  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts), do: {:ok, %{docs: %{}, next_id: 1, tick: 1}}