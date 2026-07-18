  def run(items, worker_count, process_fn, opts \\ [])
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) and is_list(opts) do
    batch = validate_batch(Keyword.get(opts, :steal_batch, :half))
    partitions = partition(items, worker_count)

    {:ok, coordinator} =
      Agent.start_link(fn ->
        partitions
        |> Enum.with_index()
        |> Map.new(fn {queue, id} -> {id, queue} end)
      end)

    worker_returns =
      0..(worker_count - 1)
      |> Enum.map(fn id ->
        Task.async(fn -> run_worker(id, coordinator, process_fn, batch) end)
      end)
      |> Task.await_many(:infinity)

    Agent.stop(coordinator)

    %{
      results: Enum.flat_map(worker_returns, & &1.results),
      metrics: build_metrics(worker_returns, worker_count)
    }
  end