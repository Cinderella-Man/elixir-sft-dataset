  test "returns error tuple for fetch functions that return {:error, reason}" do
    sources = [
      {:good, slow_ok(:fine, 10)},
      {:bad, slow_error(:something_went_wrong, 10)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 500)

    assert {:ok, :fine} = result[:good]
    assert {:error, :something_went_wrong} = result[:bad]
  end