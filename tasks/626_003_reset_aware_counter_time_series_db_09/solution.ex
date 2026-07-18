  @impl true
  def init(opts) do
    default_clock = fn -> System.monotonic_time(:millisecond) end

    state = %{
      chunk_duration_ms: Keyword.get(opts, :chunk_duration_ms, @default_chunk_duration_ms),
      clock: Keyword.get(opts, :clock, default_clock),
      retention_ms: Keyword.get(opts, :retention_ms, @default_retention_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      series: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end