  test "size never exceeds capacity", %{bm: bm} do
    for i <- 1..10 do
      BoundedBiMap.put(bm, :"k#{i}", i)
      assert BoundedBiMap.size(bm) <= 3
    end

    assert BoundedBiMap.size(bm) == 3
  end