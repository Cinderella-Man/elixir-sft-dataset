  test "exits are captured and tagged with kind :exit" do
    items = [1, 2, 3]
    results = WorkStealQueue.run(items, 2, fn x -> exit({:down, x}) end)

    assert length(results) == 3

    for %{item: item, result: result} <- results do
      assert result == {:error, %{kind: :exit, reason: {:down, item}}}
    end
  end