  @doc "Enqueues `task` at numeric `priority` (lower = higher). Returns `{:ok, ref}`."
  @spec enqueue(server(), term(), non_neg_integer()) :: {:ok, reference()}
  def enqueue(server, task, priority) when is_integer(priority) and priority >= 0 do
    GenServer.call(server, {:enqueue, task, priority})
  end