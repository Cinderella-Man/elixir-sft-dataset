  @impl true
  def init(opts) do
    {:ok,
     %{
       topics: %{},
       monitors: %{},
       next_seq: 0,
       delivery_timeout_ms: Keyword.get(opts, :delivery_timeout_ms, 5_000)
     }}
  end