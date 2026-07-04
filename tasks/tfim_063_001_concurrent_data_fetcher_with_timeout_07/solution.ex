  test "all fetches time out when all are slow" do
    sources = [
      {:a, slow_ok(:a, 500)},
      {:b, slow_ok(:b, 600)},
      {:c, slow_ok(:c, 700)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 100)

    assert {:error, :timeout} = result[:a]
    assert {:error, :timeout} = result[:b]
    assert {:error, :timeout} = result[:c]
  end