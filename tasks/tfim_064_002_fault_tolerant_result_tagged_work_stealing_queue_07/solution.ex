  test "a worker keeps processing its queue after a failing item" do
    # Every item in this worker's queue except one raises; all must be returned.
    items = Enum.to_list(1..12)

    results =
      WorkStealQueue.run(items, 1, fn x ->
        if x == 6, do: raise("only six fails"), else: x
      end)

    assert length(results) == 12
    by_item = Map.new(results, fn r -> {r.item, r.result} end)
    assert {:error, %{kind: :error}} = by_item[6]

    for x <- items, x != 6 do
      assert by_item[x] == {:ok, x}
    end
  end