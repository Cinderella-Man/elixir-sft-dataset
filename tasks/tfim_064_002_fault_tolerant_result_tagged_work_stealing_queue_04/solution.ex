  test "raised exceptions are captured and tagged, others still succeed" do
    items = Enum.to_list(1..10)

    results =
      WorkStealQueue.run(items, 3, fn x ->
        if rem(x, 2) == 0, do: raise("boom-#{x}"), else: x
      end)

    assert length(results) == 10

    by_item = Map.new(results, fn r -> {r.item, r.result} end)

    for x <- items do
      if rem(x, 2) == 0 do
        assert {:error, %{kind: :error, reason: reason}} = by_item[x]
        assert reason == "boom-#{x}"
      else
        assert by_item[x] == {:ok, x}
      end
    end
  end