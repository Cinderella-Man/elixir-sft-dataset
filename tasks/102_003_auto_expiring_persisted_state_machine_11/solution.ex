  @impl true
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    ttl = Keyword.get(opts, :pending_ttl_ms)
    {:ok, %{repo: repo, ttl: ttl, states: %{}}}
  end