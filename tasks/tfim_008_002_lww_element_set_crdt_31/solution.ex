  test "string elements work", %{s: s} do
    LWWSet.add(s, "hello", 1)
    LWWSet.add(s, "world", 2)
    assert LWWSet.member?(s, "hello") == true
    assert LWWSet.members(s) == MapSet.new(["hello", "world"])
  end