  @doc """
  Initialize the store with an empty event map.
  """
  @spec init(keyword()) :: {:ok, %{events: map()}}
  @impl GenServer
  def init(_opts), do: {:ok, %{events: %{}}}