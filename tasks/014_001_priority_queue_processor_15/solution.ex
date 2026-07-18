  @doc """
  Enqueues a task at the given priority (`:high`, `:normal`, or `:low`).
  """
  @spec enqueue(server(), term(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in [:high, :normal, :low] do
    GenServer.call(server, {:enqueue, task, priority})
  end