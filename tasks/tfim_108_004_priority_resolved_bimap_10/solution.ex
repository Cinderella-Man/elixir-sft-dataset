  test "delete removes both directions and the priority", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 5)
    assert :ok = PriorityBiMap.delete(bm, :a)

    assert :error = PriorityBiMap.get_by_key(bm, :a)
    assert :error = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.priority(bm, :a)
  end