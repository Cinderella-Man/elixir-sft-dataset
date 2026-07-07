  test "fast workers process more items than slow ones (stealing occurred)" do
    # Items 1–5 are slow, items 6–25 are fast.
    # Worker 0 gets the slow items; faster workers should steal from each other
    # and collectively outpace worker 0.
    slow_items = Enum.to_list(1..5)
    fast_items = Enum.to_list(6..25)
    items = slow_items ++ fast_items

    results =
      WorkStealQueue.run(items, 4, fn x ->
        if x <= 5 do
          # slow
          Process.sleep(50)
          x
        else
          # fast (no sleep)
          x
        end
      end)

    # All items processed
    assert length(results) == length(items)
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    # Count items per worker
    counts_by_worker =
      results
      |> Enum.group_by(& &1.worker_id)
      |> Map.new(fn {wid, rs} -> {wid, length(rs)} end)

    # The worker that handled slow items processed at most 5 items in the
    # time others processed many more. At least one other worker should
    # have processed more items than the slowest worker did.
    min_count = counts_by_worker |> Map.values() |> Enum.min()
    max_count = counts_by_worker |> Map.values() |> Enum.max()

    assert max_count > min_count,
           "Expected unequal distribution, got: #{inspect(counts_by_worker)}"
  end