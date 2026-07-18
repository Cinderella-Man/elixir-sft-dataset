  @impl true
  def init(%{processor: processor, default_ttl_ms: default_ttl_ms, clock: clock}) do
    state = %{
      queues: %{high: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      default_ttl_ms: default_ttl_ms,
      clock: clock,
      processing: false,
      current_task: nil,
      current_ref: nil,
      processed: [],
      expired: [],
      drain_waiters: []
    }

    {:ok, state}
  end