  test "key-side-only conflict is displaced and frees its old value", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)

    # Value 2 is free; :a is rebound away from 1. 20 > 10 -> accept.
    assert {:ok, evicted} = PriorityBiMap.put(bm, :a, 2, 20)
    assert evicted == [{:a, 1}]

    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 2)
    assert {:ok, 20} = PriorityBiMap.priority(bm, :a)
    # The old value must not linger in the reverse direction.
    assert :error = PriorityBiMap.get_by_value(bm, 1)
  end