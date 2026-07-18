  test "rejected key-side-only conflict leaves the requested value entirely free", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)

    # Value 2 is free; the only conflict is the pair sitting at key :a.
    assert {:error, :rejected} = PriorityBiMap.put(bm, :a, 2, 4)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
    # No partial change: value 2 was never installed.
    assert :error = PriorityBiMap.get_by_value(bm, 2)
  end