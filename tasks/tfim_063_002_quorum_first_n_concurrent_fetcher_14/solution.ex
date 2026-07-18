  test "on timeout, finished failing and crashing sources keep their real outcome" do
    sources = [
      {:err, slow_error(:nope, 10)},
      {:boom, slow_raise("kaboom", 10)},
      {:slow, slow_ok(:s, 3_000)}
    ]

    result = QuorumFetcher.fetch_first(sources, 3, 200)

    assert result[:err] == {:error, :nope}
    assert {:error, reason} = result[:boom]
    assert reason != :timeout
    assert reason != :cancelled
    assert result[:slow] == {:error, :timeout}
  end