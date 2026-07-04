  test "all success returns tagged results in order" do
    results = RetryMap.pmap(1..5, fn x -> x * 10 end, max_concurrency: 2, timeout: 1000)
    assert results == [{:ok, 10}, {:ok, 20}, {:ok, 30}, {:ok, 40}, {:ok, 50}]
  end