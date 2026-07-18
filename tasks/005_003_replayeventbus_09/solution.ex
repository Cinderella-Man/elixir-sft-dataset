  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, 60_000)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       topics: %{},
       monitors: %{},
       clock: clock,
       default_history_size: Keyword.get(opts, :default_history_size, 100),
       history_ttl_ms: Keyword.get(opts, :history_ttl_ms, 3_600_000),
       cleanup_interval_ms: cleanup_interval
     }}
  end