  test "works when collection is smaller than max_concurrency" do
    results = ParallelMap.pmap([1, 2], fn x -> x + 1 end, 10)
    assert results == [2, 3]
  end