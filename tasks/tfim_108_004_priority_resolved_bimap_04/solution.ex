  test "non-conflicting pairs install cleanly", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :a, 1, 5)
    assert {:ok, []} = PriorityBiMap.put(bm, :b, 2, 5)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :b)
  end