  test "empty sources returns empty map" do
    assert %{} == ConcurrentFetcher.fetch_all([], 1_000)
  end