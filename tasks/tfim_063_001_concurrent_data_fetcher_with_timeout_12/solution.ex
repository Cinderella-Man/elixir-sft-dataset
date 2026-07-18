  test "supports arbitrary term keys" do
    sources = [
      {"string_key", slow_ok(1, 10)},
      {42, slow_ok(2, 10)},
      {{:tuple}, slow_ok(3, 10)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 500)

    assert {:ok, 1} = result["string_key"]
    assert {:ok, 2} = result[42]
    assert {:ok, 3} = result[{:tuple}]
  end