  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    cleanup_idle = Keyword.get(opts, :cleanup_idle_ms, @default_cleanup_idle_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{bucket_name => tat_ms (float)}
       buckets: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval,
       cleanup_idle_ms: cleanup_idle
     }}
  end