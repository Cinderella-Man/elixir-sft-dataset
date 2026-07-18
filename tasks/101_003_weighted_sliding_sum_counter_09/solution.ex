  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      keys: %{}
    }

    {:ok, schedule_cleanup(state)}
  end