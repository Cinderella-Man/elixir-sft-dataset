  test "a worker processes more items than any initial queue could hold" do
    # 100 items across 4 workers partitions "as evenly as possible" into
    # local queues of exactly 25 items each — so 25 is the largest queue any
    # worker can own before stealing. The worker holding the first item is
    # blocked long enough that the other three drain their own queues and must
    # steal from it. If any worker finishes with more than 25 items, those
    # extra items can only have arrived by stealing from another worker.
    worker_count = 4
    items = Enum.to_list(0..99)
    initial_max = div(length(items) + worker_count - 1, worker_count)

    results =
      WorkStealQueue.run(items, worker_count, fn x ->
        if x == 0, do: Process.sleep(150)
        x
      end)

    assert length(results) == length(items)
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    max_count =
      results
      |> Enum.group_by(& &1.worker_id)
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.max()

    assert max_count > initial_max,
           "one worker processed #{max_count} items but no initial queue held " <>
             "more than #{initial_max}; the surplus can only come from stealing"
  end