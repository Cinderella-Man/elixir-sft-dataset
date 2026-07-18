  @impl true
  def init(%{processor: processor, max_concurrency: max_concurrency}) do
    state = %{
      queues: %{critical: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      max_concurrency: max_concurrency,
      # Map of pid => {task, monitor_ref}
      active_workers: %{},
      # Map of pid => result (received before :DOWN)
      pending_results: %{},
      processed: [],
      drain_waiters: []
    }

    {:ok, state}
  end