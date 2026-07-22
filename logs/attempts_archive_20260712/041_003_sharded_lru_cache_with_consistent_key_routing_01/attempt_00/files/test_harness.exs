defmodule LRUCacheShardedTest do
  use ExUnit.Case, async: false

  defp start_cache(num_shards, max_size) do
    name = :"shard_#{System.unique_integer([:positive])}"
    start_supervised!({LRUCacheSharded, name: name, num_shards: num_shards, max_size: max_size})
    name
  end

  # Find `count` integer keys that all route to the same shard.
  defp colliding_keys(name, count) do
    1..5000
    |> Enum.group_by(fn k -> LRUCacheSharded.shard_index(name, k) end)
    |> Enum.find_value(fn {_idx, keys} ->
      if length(keys) >= count, do: Enum.take(keys, count), else: nil
    end)
  end

  # -------------------------------------------------------
  # Single-shard behaves as a plain LRU cache
  # -------------------------------------------------------

  test "num_shards: 1 behaves like a plain LRU cache" do
    c = start_cache(1, 3)
    LRUCacheSharded.put(c, :a, 1)
    LRUCacheSharded.put(c, :b, 2)
    LRUCacheSharded.put(c, :c, 3)
    # evicts :a (LRU)
    LRUCacheSharded.put(c, :d, 4)

    assert :miss = LRUCacheSharded.get(c, :a)
    assert {:ok, 2} = LRUCacheSharded.get(c, :b)
    assert {:ok, 3} = LRUCacheSharded.get(c, :c)
    assert {:ok, 4} = LRUCacheSharded.get(c, :d)
  end

  test "get refreshes recency within a single shard" do
    c = start_cache(1, 3)
    LRUCacheSharded.put(c, :a, 1)
    LRUCacheSharded.put(c, :b, 2)
    LRUCacheSharded.put(c, :c, 3)
    # touch :a → :b becomes LRU
    LRUCacheSharded.get(c, :a)
    LRUCacheSharded.put(c, :d, 4)

    assert {:ok, 1} = LRUCacheSharded.get(c, :a)
    assert :miss = LRUCacheSharded.get(c, :b)
  end

  # -------------------------------------------------------
  # Basic API
  # -------------------------------------------------------

  test "get returns :miss for unknown key" do
    c = start_cache(4, 10)
    assert :miss = LRUCacheSharded.get(c, :nope)
  end

  test "put and get round-trip across shards" do
    c = start_cache(4, 10)
    for i <- 1..20, do: LRUCacheSharded.put(c, i, i * 100)

    for i <- 1..20 do
      expected = i * 100
      assert {:ok, ^expected} = LRUCacheSharded.get(c, i)
    end
  end

  test "num_shards reports the configured shard count" do
    c = start_cache(8, 5)
    assert LRUCacheSharded.num_shards(c) == 8
  end

  test "shard_index is deterministic and in range" do
    c = start_cache(4, 5)

    for k <- 1..50 do
      idx = LRUCacheSharded.shard_index(c, k)
      assert idx >= 0 and idx < 4
      assert LRUCacheSharded.shard_index(c, k) == idx
    end
  end

  # -------------------------------------------------------
  # Per-shard eviction
  # -------------------------------------------------------

  test "eviction is confined to the key's own shard" do
    c = start_cache(4, 2)
    [k1, k2, k3] = colliding_keys(c, 3)

    LRUCacheSharded.put(c, k1, :v1)
    LRUCacheSharded.put(c, k2, :v2)
    # shard capacity is 2 → inserting k3 evicts k1 (LRU) within that shard
    LRUCacheSharded.put(c, k3, :v3)

    assert :miss = LRUCacheSharded.get(c, k1)
    assert {:ok, :v2} = LRUCacheSharded.get(c, k2)
    assert {:ok, :v3} = LRUCacheSharded.get(c, k3)
  end

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

  # -------------------------------------------------------
  # size/1
  # -------------------------------------------------------

  test "size reports total entries across shards and respects per-shard caps" do
    c = start_cache(4, 2)
    # 4 shards * cap 2 = at most 8 entries retained
    for i <- 1..100, do: LRUCacheSharded.put(c, i, i)
    total = LRUCacheSharded.size(c)
    assert total <= 8
    assert total > 0
  end

  # -------------------------------------------------------
  # Independence between instances
  # -------------------------------------------------------

  test "two sharded caches are fully independent" do
    c1 = start_cache(2, 4)
    c2 = start_cache(2, 4)

    LRUCacheSharded.put(c1, :k, :from_c1)
    LRUCacheSharded.put(c2, :k, :from_c2)

    assert {:ok, :from_c1} = LRUCacheSharded.get(c1, :k)
    assert {:ok, :from_c2} = LRUCacheSharded.get(c2, :k)
  end
end