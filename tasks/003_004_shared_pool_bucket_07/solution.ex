  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    global_capacity = Keyword.fetch!(opts, :global_capacity)
    global_refill_rate = Keyword.fetch!(opts, :global_refill_rate) * 1.0

    now = clock.()
    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       buckets: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval,
       # Global pool — lives at top level, not in buckets map.
       global_free: global_capacity * 1.0,
       global_capacity: global_capacity,
       global_refill_rate: global_refill_rate,
       global_last_update_at: now
     }}
  end