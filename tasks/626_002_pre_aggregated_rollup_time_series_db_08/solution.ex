  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    bucket_duration_ms = Keyword.get(opts, :bucket_duration_ms, @default_bucket_duration_ms)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    retention_ms = Keyword.get(opts, :retention_ms, @default_retention_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      bucket_duration_ms: bucket_duration_ms,
      clock: clock,
      retention_ms: retention_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      series: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end