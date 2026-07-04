  test "returns a map with results and metrics; all items processed once" do
    items = Enum.to_list(1..20)
    %{results: results, metrics: metrics} = WorkStealQueue.run(items, 4, fn x -> x * 2 end)

    assert length(results) == 20
    assert Enum.sort(processed_items(results)) == Enum.sort(items)
    assert length(Enum.uniq_by(results, & &1.item)) == 20

    # metrics keys cover every worker id
    assert Map.keys(metrics.processed) |> Enum.sort() == [0, 1, 2, 3]
    assert Map.keys(metrics.steals) |> Enum.sort() == [0, 1, 2, 3]
    assert Map.keys(metrics.stolen) |> Enum.sort() == [0, 1, 2, 3]
  end