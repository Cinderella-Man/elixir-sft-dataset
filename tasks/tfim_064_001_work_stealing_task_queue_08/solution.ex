  test "single worker processes all items without stealing" do
    items = Enum.to_list(1..10)
    results = WorkStealQueue.run(items, 1, fn x -> x + 1 end)

    assert length(results) == 10
    assert Enum.map(results, & &1.worker_id) |> Enum.uniq() == [0]
    assert Enum.sort(processed_items(results)) == items
  end