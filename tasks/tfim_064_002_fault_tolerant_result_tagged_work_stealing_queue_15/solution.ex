  test "duplicate items each get their own result entry" do
    items = [:dup, :dup, :dup, :other, :dup]
    results = WorkStealQueue.run(items, 3, fn x -> x end)

    assert length(results) == 5
    assert Enum.count(results, &(&1.item == :dup)) == 4
    assert Enum.count(results, &(&1.item == :other)) == 1
    assert Enum.all?(results, fn r -> r.result == {:ok, r.item} end)
  end