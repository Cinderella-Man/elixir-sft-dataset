  test "falls through to the next fallback on error" do
    result = FallbackFetcher.fetch_all([{:a, [fast_error(:down), fast_ok(:backup)]}], 1_000)
    assert result[:a] == {:ok, :backup}
  end