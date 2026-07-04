  test "mix of fast, slow, and failing sources" do
    sources = [
      {:fast, slow_ok(:winner, 20)},
      {:slow, slow_ok(:loser, 800)},
      {:crasher, slow_raise("oops", 10)},
      {:erring, slow_error(:bad_input, 10)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 200)

    assert {:ok, :winner} = result[:fast]
    assert {:error, :timeout} = result[:slow]
    assert {:error, _} = result[:crasher]
    assert {:error, :bad_input} = result[:erring]
  end