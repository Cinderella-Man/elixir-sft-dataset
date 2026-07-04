  test "still-running sources become :timeout when the quorum can't be met in time" do
    sources = [
      {:a, slow_ok(:a, 10)},
      {:b, slow_ok(:b, 10)},
      {:c, slow_ok(:c, 3_000)},
      {:d, slow_ok(:d, 3_000)},
      {:e, slow_ok(:e, 3_000)}
    ]

    result = QuorumFetcher.fetch_first(sources, 5, 150)

    assert result[:a] == {:ok, :a}
    assert result[:b] == {:ok, :b}
    assert result[:c] == {:error, :timeout}
    assert result[:d] == {:error, :timeout}
    assert result[:e] == {:error, :timeout}
  end