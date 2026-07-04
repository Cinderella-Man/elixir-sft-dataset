  test "empty sources returns an empty map" do
    assert PooledFetcher.fetch_all([], 3, 1_000) == %{}
  end