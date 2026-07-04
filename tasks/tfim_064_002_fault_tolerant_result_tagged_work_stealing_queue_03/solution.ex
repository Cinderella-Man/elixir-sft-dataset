  test "successful results are tagged {:ok, value}" do
    items = Enum.to_list(1..10)
    results = WorkStealQueue.run(items, 2, fn x -> x * x end)

    for %{item: item, result: result} <- results do
      assert result == {:ok, item * item}
    end
  end