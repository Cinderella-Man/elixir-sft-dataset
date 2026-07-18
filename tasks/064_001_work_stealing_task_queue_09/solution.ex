  def run(items, worker_count, process_fn)
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) do
    # Divide the input list into `worker_count` chunks as evenly as possible.
    partitions = partition(items, worker_count)

    # The coordinator Agent holds a map of %{id => remaining_queue}.
    # All queue mutations (pop, steal) go through this Agent so they are
    # serialised and workers see a consistent picture of who has work left.
    {:ok, coordinator} =
      Agent.start_link(fn ->
        partitions
        |> Enum.with_index()
        |> Map.new(fn {queue, id} -> {id, queue} end)
      end)

    # Spawn one Task per worker and await all of them.
    results =
      0..(worker_count - 1)
      |> Enum.map(fn id ->
        Task.async(fn -> run_worker(id, coordinator, process_fn) end)
      end)
      |> Task.await_many(:infinity)
      |> List.flatten()

    Agent.stop(coordinator)
    results
  end