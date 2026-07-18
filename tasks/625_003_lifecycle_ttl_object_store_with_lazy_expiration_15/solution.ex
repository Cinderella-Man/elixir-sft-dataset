  @impl true
  @spec init(map()) :: {:ok, map()}
  def init(%{default_ttl_ms: default_ttl}) do
    {:ok, %{default_ttl_ms: default_ttl, buckets: %{}}}
  end