  test "a freed key/value can be re-used at any priority", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.delete(bm, :a)

    # Value 1 is free again, so even a low priority installs cleanly.
    assert {:ok, []} = PriorityBiMap.put(bm, :b, 1, 1)
    assert {:ok, :b} = PriorityBiMap.get_by_value(bm, 1)
  end