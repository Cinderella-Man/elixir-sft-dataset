  @doc """
  Initializes the store state with an empty stream registry.
  """
  @spec init(keyword()) :: {:ok, map()}
  @impl GenServer
  def init(_opts), do: {:ok, %{streams: %{}}}