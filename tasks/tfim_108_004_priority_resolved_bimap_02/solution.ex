  test "put then look up in both directions", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :a, 1, 10)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
  end