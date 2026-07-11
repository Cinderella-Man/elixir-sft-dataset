  test "double conflict displaces both pairs when priority wins", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.put(bm, :b, 2, 10)

    # :a wants value 2. Conflicts: (a,1,10) key-side and (b,2,10) value-side.
    assert {:ok, evicted} = PriorityBiMap.put(bm, :a, 2, 15)
    assert Enum.sort(evicted) == Enum.sort([{:a, 1}, {:b, 2}])

    # Surviving pair is consistent both ways.
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 2)
    # Both old associations are gone.
    assert :error = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.get_by_key(bm, :b)
    assert {:ok, 15} = PriorityBiMap.priority(bm, :a)
  end