  test "process_fn returning complex terms works" do
    items = [:a, :b, :c]
    results = WorkStealQueue.run(items, 2, fn x -> {x, to_string(x)} end)

    assert length(results) == 3

    for %{item: item, result: result} <- results do
      assert result == {item, to_string(item)}
    end
  end