  test "a chain that overruns the global timeout is reported as :timeout" do
    sources = [
      {:fast, [fast_ok(:done)]},
      {:slow, [slow_ok(:never, 2_000)]}
    ]

    result = FallbackFetcher.fetch_all(sources, 150)

    assert result[:fast] == {:ok, :done}
    assert result[:slow] == {:error, :timeout}
  end