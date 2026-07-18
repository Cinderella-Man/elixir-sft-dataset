  # Entry-point for each worker Task.  Results accumulate tail-recursively.
  defp run_worker(id, coordinator, process_fn) do
    process_local_queue(id, coordinator, process_fn, _acc = [])
  end