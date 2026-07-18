  @impl true
  def init(%{processor: processor}) do
    state = %{
      queues: %{},
      processor: processor,
      processing: false,
      current_task: nil,
      current_ref: nil,
      processed: [],
      cancelled_count: 0,
      drain_waiters: []
    }

    {:ok, state}
  end