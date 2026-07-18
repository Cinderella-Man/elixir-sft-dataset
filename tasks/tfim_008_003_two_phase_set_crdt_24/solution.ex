  test "many elements", %{s: s} do
    for i <- 1..100 do
      TwoPhaseSet.add(s, :"elem_#{i}")
    end

    assert MapSet.size(TwoPhaseSet.members(s)) == 100
  end