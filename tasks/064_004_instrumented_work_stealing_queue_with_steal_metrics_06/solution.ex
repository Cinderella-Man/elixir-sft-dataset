  defp run_worker(id, coordinator, process_fn, batch) do
    loop(id, coordinator, process_fn, batch, %{
      worker_id: id,
      results: [],
      steals: 0,
      stolen: 0
    })
  end