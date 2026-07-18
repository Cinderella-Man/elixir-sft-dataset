  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts), do: {:ok, %{files: %{}}}