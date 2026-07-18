  test "string elements work", %{s: s} do
    ORSet.add(s, "hello", :n1)
    ORSet.add(s, "world", :n1)
    assert ORSet.member?(s, "hello") == true
    assert ORSet.members(s) == MapSet.new(["hello", "world"])
  end