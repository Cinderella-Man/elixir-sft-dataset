  test "mixes success, exhausted fallbacks, and timeout" do
    sources = [
      {:ok_src, [fast_error(:x), fast_ok(:good)]},
      {:dead, [fast_error(:a), fast_error(:b)]},
      {:slow, [slow_ok(:never, 2_000)]}
    ]

    result = FallbackFetcher.fetch_all(sources, 150)

    assert result[:ok_src] == {:ok, :good}
    assert {:error, {:all_failed, [:a, :b]}} = result[:dead]
    assert result[:slow] == {:error, :timeout}
  end