  test "returns error tuple for fetch functions that raise" do
    sources = [
      {:good, slow_ok(:fine, 10)},
      {:bad, slow_raise("boom", 10)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 500)

    assert {:ok, :fine} = result[:good]
    assert {:error, reason} = result[:bad]
    assert reason != :timeout
  end