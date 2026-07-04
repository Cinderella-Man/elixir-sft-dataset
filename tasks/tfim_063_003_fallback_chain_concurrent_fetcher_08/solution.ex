  test "empty sources returns an empty map" do
    assert FallbackFetcher.fetch_all([], 1_000) == %{}
  end