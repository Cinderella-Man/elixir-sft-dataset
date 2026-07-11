  test "re-putting the same pair updates its priority and displaces nothing", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 3)
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 7)

    assert {:ok, 9} = PriorityBiMap.get_by_key(bm, :x)
    assert {:ok, 7} = PriorityBiMap.priority(bm, :x)
  end