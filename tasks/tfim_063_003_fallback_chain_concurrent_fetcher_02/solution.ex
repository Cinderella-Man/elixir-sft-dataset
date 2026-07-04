  test "uses the first fallback when it succeeds" do
    result = FallbackFetcher.fetch_all([{:a, [fast_ok(:first), fast_ok(:second)]}], 1_000)
    assert result[:a] == {:ok, :first}
  end