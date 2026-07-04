  test "worker_count greater than item count still processes everything" do
    items = [1, 2, 3]
    %{results: results, metrics: metrics} = WorkStealQueue.run(items, 10, fn x -> x end)

    assert length(results) == 3
    assert Enum.sort(processed_items(results)) == [1, 2, 3]
    assert Map.keys(metrics.processed) |> Enum.sort() == Enum.to_list(0..9)
  end