  def submit(pool, task_func, opts \\ []) when is_function(task_func, 0) do
    GenServer.call(pool, {:submit, task_func, opts})
  end