  test "maps over an empty collection" do
    assert [] = ParallelMap.pmap([], fn x -> x * 2 end, 3)
  end