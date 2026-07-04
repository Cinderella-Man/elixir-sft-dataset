  test "empty sources returns an empty map" do
    assert QuorumFetcher.fetch_first([], 3, 1_000) == %{}
  end