  test "single add makes element a member", %{s: s} do
    assert :ok = ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
    assert ORSet.members(s) == MapSet.new([:x])
  end