  test "put beating one conflict but tying the other is rejected with no partial eviction", %{
    bm: bm
  } do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.put(bm, :b, 2, 7)

    # :a wants value 2. Conflicts: (a,1,10) key-side and (b,2,7) value-side.
    # 8 beats the value-side pair but not the key-side pair -> reject everything.
    assert {:error, :rejected} = PriorityBiMap.put(bm, :a, 2, 8)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :b)
    assert {:ok, :b} = PriorityBiMap.get_by_value(bm, 2)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
    assert {:ok, 7} = PriorityBiMap.priority(bm, :b)
  end