  @doc """
  Initializes the store with an empty file map.
  """
  @spec init(keyword()) :: {:ok, %{files: map()}}
  @impl true
  def init(_opts), do: {:ok, %{files: %{}}}