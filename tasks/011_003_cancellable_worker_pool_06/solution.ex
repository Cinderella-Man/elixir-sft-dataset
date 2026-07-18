  @doc "Submits `task_func` to the pool. Returns `{:ok, ref}` or `{:error, :queue_full}`."
  @spec submit(GenServer.server(), (-> any())) :: {:ok, reference()} | {:error, :queue_full}
  def submit(pool, task_func) when is_function(task_func, 0) do
    GenServer.call(pool, {:submit, task_func})
  end