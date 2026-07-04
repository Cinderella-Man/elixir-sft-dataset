  test "returns ok for all sources when the pool is large enough" do
    sources = [
      {:a, slow_ok(:ra, 10)},
      {:b, slow_ok(:rb, 10)},
      {:c, slow_ok(:rc, 10)}
    ]

    result = PooledFetcher.fetch_all(sources, 5, 1_000)

    assert result == %{a: {:ok, :ra}, b: {:ok, :rb}, c: {:ok, :rc}}
  end