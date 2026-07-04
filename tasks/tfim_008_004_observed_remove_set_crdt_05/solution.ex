  test "remove after add removes element", %{s: s} do
    ORSet.add(s, :x, :node_a)
    assert :ok = ORSet.remove(s, :x)
    assert ORSet.member?(s, :x) == false
    assert ORSet.members(s) == MapSet.new()
  end