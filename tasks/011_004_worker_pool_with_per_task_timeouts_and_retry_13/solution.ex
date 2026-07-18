  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {RetryPool.Worker, [self()]})
  end