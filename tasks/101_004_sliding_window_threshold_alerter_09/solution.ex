  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      bucket_ms: Keyword.get(opts, :bucket_ms, @default_bucket_ms),
      threshold: Keyword.get(opts, :threshold, @default_threshold),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      keys: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end