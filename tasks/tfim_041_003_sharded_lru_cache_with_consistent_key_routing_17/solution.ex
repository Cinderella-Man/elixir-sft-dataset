  test "arbitrary terms work as keys and values and round-trip unchanged" do
    c = start_cache(2, 8)

    pairs = [
      {nil, nil},
      {{:tuple, 1}, %{nested: [1, 2, 3]}},
      {"string", {:ok, nil}},
      {~D[2024-01-01], ~D[2030-12-31]},
      {[1, [2]], :atom_value}
    ]

    for {k, v} <- pairs, do: LRUCacheSharded.put(c, k, v)

    for {k, v} <- pairs do
      idx = LRUCacheSharded.shard_index(c, k)
      assert idx >= 0 and idx < 2
      assert {:ok, ^v} = LRUCacheSharded.get(c, k)
    end
  end