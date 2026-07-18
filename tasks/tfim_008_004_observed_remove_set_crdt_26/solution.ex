  test "many elements", %{s: s} do
    for i <- 1..100 do
      ORSet.add(s, :"elem_#{i}", :node)
    end

    assert MapSet.size(ORSet.members(s)) == 100
  end