  test "many elements with small timestamps", %{s: s} do
    for i <- 1..100 do
      LWWSet.add(s, :"elem_#{i}", 1)
    end

    assert MapSet.size(LWWSet.members(s)) == 100
  end