  test "empty collection returns []" do
    assert [] = RetryMap.pmap([], fn x -> x end, max_concurrency: 3)
  end