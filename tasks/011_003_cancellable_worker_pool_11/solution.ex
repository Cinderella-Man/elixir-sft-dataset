  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {CancellablePool.Worker, [self()]})
  end