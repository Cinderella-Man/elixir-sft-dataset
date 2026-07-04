  test "add with higher timestamp after remove re-adds element", %{s: s} do
    LWWSet.add(s, :x, 1)
    LWWSet.remove(s, :x, 2)
    LWWSet.add(s, :x, 3)
    assert LWWSet.member?(s, :x) == true
  end