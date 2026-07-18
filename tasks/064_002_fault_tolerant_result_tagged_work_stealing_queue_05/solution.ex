  defp run_worker(id, coordinator, process_fn) do
    process_local_queue(id, coordinator, process_fn, [])
  end