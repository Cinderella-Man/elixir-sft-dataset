  test "lower-priority put across two pairs is rejected and changes nothing", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.put(bm, :b, 2, 10)

    # :a wants value 2 (held by :b) — conflicts with (a,1,10) and (b,2,10).
    assert {:error, :rejected} = PriorityBiMap.put(bm, :a, 2, 5)

    # Nothing moved.
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :b)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, :b} = PriorityBiMap.get_by_value(bm, 2)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
  end