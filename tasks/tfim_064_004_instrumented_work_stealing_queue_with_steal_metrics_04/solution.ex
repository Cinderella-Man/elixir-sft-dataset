  test "processed metric matches actual result distribution and totals" do
    items = Enum.to_list(1..40)
    %{results: results, metrics: metrics} = WorkStealQueue.run(items, 4, fn x -> x end)

    total_processed = metrics.processed |> Map.values() |> Enum.sum()
    assert total_processed == 40

    counts =
      results
      |> Enum.group_by(& &1.worker_id)
      |> Map.new(fn {wid, rs} -> {wid, length(rs)} end)

    for wid <- 0..3 do
      assert metrics.processed[wid] == Map.get(counts, wid, 0)
    end
  end