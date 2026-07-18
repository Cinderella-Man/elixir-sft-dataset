  @doc "Enqueues `task` at `priority` with a per-task TTL from `opts`. Returns `:ok`."
  @spec enqueue(server(), term(), priority(), keyword()) :: :ok
  def enqueue(server, task, priority, opts \\ []) when priority in [:high, :normal, :low] do
    GenServer.call(server, {:enqueue, task, priority, opts})
  end