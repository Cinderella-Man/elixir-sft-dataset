  test "worker_count greater than item count still processes everything" do
    items = [1, 2, 3]
    results = WorkStealQueue.run(items, 10, fn x -> x end)

    assert length(results) == 3
    assert Enum.sort(processed_items(results)) == [1, 2, 3]
  end