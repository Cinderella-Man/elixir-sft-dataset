  test "works with max_concurrency equal to collection size" do
    results = ParallelMap.pmap([1, 2, 3], fn x -> x + 100 end, 3)
    assert results == [101, 102, 103]
  end