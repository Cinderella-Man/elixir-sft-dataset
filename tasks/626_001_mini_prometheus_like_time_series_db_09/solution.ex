  @impl true
  def init(opts) do
    chunk_duration_ms = Keyword.get(opts, :chunk_duration_ms, @default_chunk_duration_ms)
    retention_ms = Keyword.get(opts, :retention_ms, @default_retention_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      series: %{},
      chunk_duration_ms: chunk_duration_ms,
      retention_ms: retention_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(state)

    {:ok, state}
  end