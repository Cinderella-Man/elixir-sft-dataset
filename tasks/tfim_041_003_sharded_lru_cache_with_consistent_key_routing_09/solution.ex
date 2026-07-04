  test "filling one shard does not evict entries in another shard" do
    c = start_cache(4, 2)

    grouped =
      1..5000
      |> Enum.group_by(fn k -> LRUCacheSharded.shard_index(c, k) end)

    # pick two distinct shards that each have at least 3 keys
    [{_ia, a_keys}, {_ib, b_keys} | _] =
      grouped
      |> Enum.filter(fn {_i, ks} -> length(ks) >= 3 end)
      |> Enum.take(2)

    [a1, a2, a3] = Enum.take(a_keys, 3)
    [b1 | _] = b_keys

    # park a survivor in shard B
    LRUCacheSharded.put(c, b1, :survivor)

    # overflow shard A
    LRUCacheSharded.put(c, a1, 1)
    LRUCacheSharded.put(c, a2, 2)
    LRUCacheSharded.put(c, a3, 3)

    # a1 evicted from shard A, but shard B's entry is untouched
    assert :miss = LRUCacheSharded.get(c, a1)
    assert {:ok, :survivor} = LRUCacheSharded.get(c, b1)
  end