  test "remove after add with higher timestamp removes element", %{s: s} do
    LWWSet.add(s, :x, 1)
    assert :ok = LWWSet.remove(s, :x, 2)
    assert LWWSet.member?(s, :x) == false
    assert LWWSet.members(s) == MapSet.new()
  end