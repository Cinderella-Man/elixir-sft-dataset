  test "a non-positive quorum cancels every source without running it" do
    sources = [
      {:a, slow_ok(:a, 10)},
      {:b, slow_ok(:b, 10)}
    ]

    result = QuorumFetcher.fetch_first(sources, 0, 1_000)

    assert result == %{a: {:error, :cancelled}, b: {:error, :cancelled}}
  end