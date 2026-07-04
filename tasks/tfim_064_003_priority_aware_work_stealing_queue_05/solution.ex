  test "idle workers steal low-priority items; owners keep their most urgent work" do
    # Partition of 8 items across 2 workers:
    #   worker 0 gets the first 4 (priorities 8,7,6,5 -> all slow)
    #   worker 1 gets the last 4  (priorities 4,3,2,1 -> all fast)
    # Worker 1 races through its fast items, then steals the LOW-priority
    # remainder of worker 0. Worker 0 always processes its top item (8) first.
    items = [{8, 8}, {7, 7}, {6, 6}, {5, 5}, {4, 4}, {3, 3}, {2, 2}, {1, 1}]

    results =
      WorkStealQueue.run(items, 2, fn payload ->
        if payload >= 5, do: Process.sleep(40)
        payload
      end)

    assert length(results) == 8

    worker_by_priority = Map.new(results, fn r -> {r.priority, r.worker_id} end)

    # The most urgent item is retained and processed by its owner (worker 0).
    assert worker_by_priority[8] == 0

    # At least one of worker 0's lower-priority items was stolen by worker 1.
    assert Enum.any?([5, 6, 7], fn p -> worker_by_priority[p] == 1 end),
           "Expected a low-priority item to be stolen, got: #{inspect(worker_by_priority)}"
  end