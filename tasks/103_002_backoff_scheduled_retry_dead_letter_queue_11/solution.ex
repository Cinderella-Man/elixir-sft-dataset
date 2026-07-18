  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      base: Keyword.get(opts, :base_backoff_ms, 1000),
      max_attempts: Keyword.get(opts, :max_attempts, 5),
      next_id: 0,
      queues: %{}
    }

    {:ok, state}
  end