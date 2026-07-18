  @impl true
  def init(opts) do
    clock =
      Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    max_window_ms = Keyword.get(opts, :max_window_ms, bucket_ms * @default_max_window_buckets)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      max_window_ms: max_window_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      # Primary data structure.
      # Outer map key  → key supplied by the caller (any term).
      # Inner map key  → bucket index (integer).
      # Inner map value → event count (positive integer).
      keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end