  test "steal_batch: 1 still completes all work" do
    items = Enum.to_list(1..30)

    %{results: results, metrics: metrics} =
      WorkStealQueue.run(
        items,
        4,
        fn x ->
          if x <= 4, do: Process.sleep(30)
          x
        end,
        steal_batch: 1
      )

    assert length(results) == 30
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    total_processed = metrics.processed |> Map.values() |> Enum.sum()
    assert total_processed == 30
  end