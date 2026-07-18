  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {PriorityWorkerPool.Worker, [self()]})
  end