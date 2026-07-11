  test "reassigning across existing entries preserves the bijection", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :b, 2)

    # :a wants value 2, which currently belongs to :b
    BiMap.put(bm, :a, 2)

    # :b lost its value (value 2 was reassigned to :a)
    assert :error = BiMap.get_by_key(bm, :b)
    # :a's old value 1 is orphaned
    assert :error = BiMap.get_by_value(bm, 1)

    # Surviving pair is consistent both ways
    assert {:ok, 2} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, 2)
  end