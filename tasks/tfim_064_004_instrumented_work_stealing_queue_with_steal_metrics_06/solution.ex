  test "imbalanced load produces measurable steals" do
    slow_items = Enum.to_list(1..5)
    fast_items = Enum.to_list(6..25)
    items = slow_items ++ fast_items

    %{results: results, metrics: metrics} =
      WorkStealQueue.run(items, 4, fn x ->
        if x <= 5, do: Process.sleep(50)
        x
      end)

    assert length(results) == length(items)
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    total_steals = metrics.steals |> Map.values() |> Enum.sum()
    total_stolen = metrics.stolen |> Map.values() |> Enum.sum()

    assert total_steals > 0, "Expected at least one steal, got: #{inspect(metrics.steals)}"
    assert total_stolen >= total_steals
  end