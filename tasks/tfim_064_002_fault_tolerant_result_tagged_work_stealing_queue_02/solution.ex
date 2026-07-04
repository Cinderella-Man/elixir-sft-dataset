  test "all items are returned exactly once" do
    items = Enum.to_list(1..20)
    results = WorkStealQueue.run(items, 4, fn x -> x * 2 end)

    assert length(results) == 20
    assert Enum.sort(processed_items(results)) == Enum.sort(items)
    assert length(Enum.uniq_by(results, & &1.item)) == 20
  end