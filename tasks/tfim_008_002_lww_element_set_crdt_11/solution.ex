  test "multiple elements tracked independently", %{s: s} do
    LWWSet.add(s, :a, 1)
    LWWSet.add(s, :b, 2)
    LWWSet.add(s, :c, 3)
    LWWSet.remove(s, :b, 4)

    assert LWWSet.members(s) == MapSet.new([:a, :c])
    assert LWWSet.member?(s, :a) == true
    assert LWWSet.member?(s, :b) == false
    assert LWWSet.member?(s, :c) == true
  end