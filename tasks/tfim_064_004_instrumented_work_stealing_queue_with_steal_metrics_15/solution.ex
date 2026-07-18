  test "duplicate items each get their own result entry" do
    items = [1, 1, 2, 2, 2, 3]
    %{results: results, metrics: metrics} = WorkStealQueue.run(items, 3, fn x -> x * 10 end)

    assert length(results) == 6
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    for %{item: item, result: result} <- results do
      assert result == item * 10
    end

    assert metrics.processed |> Map.values() |> Enum.sum() == 6
  end