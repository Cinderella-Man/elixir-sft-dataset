  test "thrown values are captured and tagged with kind :throw" do
    items = [:a, :b, :c]
    results = WorkStealQueue.run(items, 2, fn x -> throw({:bad, x}) end)

    assert length(results) == 3

    for %{item: item, result: result} <- results do
      assert result == {:error, %{kind: :throw, reason: {:bad, item}}}
    end
  end