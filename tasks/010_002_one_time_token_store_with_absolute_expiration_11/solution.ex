  @impl GenServer
  def init(opts) do
    default_ttl_ms = Keyword.get(opts, :default_ttl_ms, @default_ttl_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      tokens: %{},
      default_ttl_ms: default_ttl_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end