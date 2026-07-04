  test "empty collection returns []" do
    assert [] = WeightedMap.pmap([], fn x -> x end, fn _ -> 1 end, 5)
  end