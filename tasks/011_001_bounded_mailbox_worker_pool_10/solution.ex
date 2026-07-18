  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {WorkerPool.Worker, [self()]})
  end