  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      max_window_ms: max_window_ms,
      keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end