  test "element can be re-added after removal", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.remove(s, :x)
    assert ORSet.member?(s, :x) == false

    ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
  end