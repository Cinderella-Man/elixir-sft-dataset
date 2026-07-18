  test "re-putting the same pair at a lower priority lowers the stored priority", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 30)
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 2)

    assert {:ok, 9} = PriorityBiMap.get_by_key(bm, :x)
    assert {:ok, :x} = PriorityBiMap.get_by_value(bm, 9)
    assert {:ok, 2} = PriorityBiMap.priority(bm, :x)

    # The lowered priority really governs later conflicts.
    assert {:ok, [{:x, 9}]} = PriorityBiMap.put(bm, :y, 9, 3)
  end