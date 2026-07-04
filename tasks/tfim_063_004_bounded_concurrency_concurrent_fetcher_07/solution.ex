  test "supports arbitrary term keys" do
    sources = [
      {"s", slow_ok(1, 10)},
      {42, slow_ok(2, 10)},
      {{:t}, slow_ok(3, 10)}
    ]

    result = PooledFetcher.fetch_all(sources, 3, 1_000)

    assert result["s"] == {:ok, 1}
    assert result[42] == {:ok, 2}
    assert result[{:t}] == {:ok, 3}
  end