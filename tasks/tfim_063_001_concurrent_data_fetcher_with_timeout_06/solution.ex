  test "slow fetches are reported as :timeout" do
    sources = [
      {:fast, slow_ok(:done, 20)},
      {:slow, slow_ok(:never, 600)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 150)

    assert {:ok, :done} = result[:fast]
    assert {:error, :timeout} = result[:slow]
  end