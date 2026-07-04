  test "fast workers pick up slack, and errors do not break stealing" do
    slow_items = Enum.to_list(1..5)
    fast_items = Enum.to_list(6..25)
    items = slow_items ++ fast_items

    results =
      WorkStealQueue.run(items, 4, fn x ->
        cond do
          x <= 5 ->
            Process.sleep(50)
            x

          rem(x, 3) == 0 ->
            raise("fast-failure-#{x}")

          true ->
            x
        end
      end)

    assert length(results) == length(items)
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    counts_by_worker =
      results
      |> Enum.group_by(& &1.worker_id)
      |> Map.new(fn {wid, rs} -> {wid, length(rs)} end)

    min_count = counts_by_worker |> Map.values() |> Enum.min()
    max_count = counts_by_worker |> Map.values() |> Enum.max()

    assert max_count > min_count,
           "Expected work stealing to cause unequal distribution, got: #{inspect(counts_by_worker)}"
  end