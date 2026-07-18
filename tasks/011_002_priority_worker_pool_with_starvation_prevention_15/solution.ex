  def submit(pool, task_func, priority \\ :normal)
      when is_function(task_func, 0) and priority in @priorities do
    GenServer.call(pool, {:submit, task_func, priority})
  end