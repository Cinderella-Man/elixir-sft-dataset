  @impl true
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      processor: Keyword.get(opts, :processor, fn _params -> :ok end),
      counter: 0,
      payments: [],
      # key => {:completed, result, expiry} | {:pending, [from]}
      idempotency_keys: %{},
      # ref => from  (in-flight requests without an idempotency key)
      nil_pending: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end