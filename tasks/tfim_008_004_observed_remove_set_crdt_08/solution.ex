  test "multiple add-remove cycles work", %{s: s} do
    for _i <- 1..5 do
      ORSet.add(s, :x, :node_a)
      assert ORSet.member?(s, :x) == true
      ORSet.remove(s, :x)
      assert ORSet.member?(s, :x) == false
    end

    ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
  end