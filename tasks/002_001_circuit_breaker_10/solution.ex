  @impl true
  def init(opts) do
    state = %{
      circuit_state: :closed,
      failure_count: 0,
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, 30_000),
      half_open_max_probes: Keyword.get(opts, :half_open_max_probes, 1),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      opened_at: nil,
      probe_count: 0
    }

    {:ok, state}
  end