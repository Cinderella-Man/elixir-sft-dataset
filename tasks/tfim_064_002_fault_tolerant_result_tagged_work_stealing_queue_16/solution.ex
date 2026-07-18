  test "one item per worker means every worker_id appears exactly once" do
    items = Enum.to_list(1..6)
    results = WorkStealQueue.run(items, 6, fn x -> x end)

    assert length(results) == 6
    assert results |> Enum.map(& &1.worker_id) |> Enum.sort() == Enum.to_list(0..5)
  end