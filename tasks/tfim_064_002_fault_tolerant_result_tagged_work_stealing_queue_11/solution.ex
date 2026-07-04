  test "single worker processes all items without stealing" do
    items = Enum.to_list(1..10)
    results = WorkStealQueue.run(items, 1, fn x -> x + 1 end)

    assert length(results) == 10
    assert worker_ids(results) == [0]

    for %{item: item, result: result} <- results do
      assert result == {:ok, item + 1}
    end
  end