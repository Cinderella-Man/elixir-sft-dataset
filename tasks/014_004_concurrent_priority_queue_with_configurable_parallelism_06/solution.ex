  @doc "Enqueues `task` at `priority` for concurrent processing. Returns `:ok`."
  @spec enqueue(server(), term(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in @priority_order do
    GenServer.call(server, {:enqueue, task, priority})
  end