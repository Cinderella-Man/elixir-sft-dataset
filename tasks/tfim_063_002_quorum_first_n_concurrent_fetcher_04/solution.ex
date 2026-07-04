  test "a crashing source is reported as an error, not a success" do
    sources = [
      {:boom, slow_raise("kaboom", 10)},
      {:win, slow_ok(:yes, 120)}
    ]

    result = QuorumFetcher.fetch_first(sources, 1, 1_000)

    assert {:error, reason} = result[:boom]
    assert reason != :cancelled
    assert reason != :timeout
    assert result[:win] == {:ok, :yes}
  end