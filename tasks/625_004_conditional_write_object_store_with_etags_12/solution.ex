  @impl true
  @spec init(term()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %{buckets: %{}}}
  end