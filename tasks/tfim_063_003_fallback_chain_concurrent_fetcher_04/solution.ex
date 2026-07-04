  test "treats a raising fallback as a failure and continues" do
    result = FallbackFetcher.fetch_all([{:a, [fast_raise("boom"), fast_ok(:recovered)]}], 1_000)
    assert result[:a] == {:ok, :recovered}
  end