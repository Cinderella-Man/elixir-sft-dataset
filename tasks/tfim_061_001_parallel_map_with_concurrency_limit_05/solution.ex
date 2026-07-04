  test "works with max_concurrency of 1 (sequential)" do
    results = ParallelMap.pmap([3, 1, 2], fn x -> x * x end, 1)
    assert results == [9, 1, 4]
  end