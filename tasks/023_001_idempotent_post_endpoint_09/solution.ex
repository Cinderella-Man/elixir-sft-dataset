  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      ttl_ms: ttl_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      counter: 0,
      payments: [],
      idempotency_keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end