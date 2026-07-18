  test "error-shaped and nil return values are still tagged as successes" do
    items = [:nil_item, :err_item, :exit_item]

    results =
      WorkStealQueue.run(items, 2, fn
        :nil_item -> nil
        :err_item -> {:error, %{kind: :error, reason: "not really raised"}}
        :exit_item -> {:exit, :boom}
      end)

    by_item = Map.new(results, fn r -> {r.item, r.result} end)

    assert by_item[:nil_item] == {:ok, nil}
    assert by_item[:err_item] == {:ok, {:error, %{kind: :error, reason: "not really raised"}}}
    assert by_item[:exit_item] == {:ok, {:exit, :boom}}
  end