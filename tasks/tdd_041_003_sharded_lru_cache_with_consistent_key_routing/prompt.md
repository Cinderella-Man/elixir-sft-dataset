# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
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

  test "updating a key at exactly capacity evicts nothing and refreshes its recency" do
    c = start_cache(1, 2)
    LRUCacheSharded.put(c, :a, 1)
    LRUCacheSharded.put(c, :b, 2)
    assert LRUCacheSharded.size(c) == 2

    # in-place update while the shard is exactly full
    LRUCacheSharded.put(c, :a, 99)
    assert LRUCacheSharded.size(c) == 2

    # :a was refreshed by the update, so :b is now the eviction victim
    LRUCacheSharded.put(c, :c, 3)
    assert :miss = LRUCacheSharded.get(c, :b)
    assert {:ok, 99} = LRUCacheSharded.get(c, :a)
    assert {:ok, 3} = LRUCacheSharded.get(c, :c)
    assert LRUCacheSharded.size(c) == 2
  end

  test "invalid :num_shards fails the start with an ArgumentError naming the option" do
    Process.flag(:trap_exit, true)
    n1 = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{message: m1}, _stack}} =
             LRUCacheSharded.start_link(name: n1, num_shards: 0, max_size: 4)

    assert m1 =~ ":num_shards"
    assert m1 =~ "0"

    n2 = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{message: m2}, _stack}} =
             LRUCacheSharded.start_link(name: n2, num_shards: 2.0, max_size: 4)

    assert m2 =~ ":num_shards"
    assert m2 =~ "2.0"
  end

  test "invalid :max_size fails the start with an ArgumentError naming the option" do
    Process.flag(:trap_exit, true)
    n1 = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{message: m1}, _stack}} =
             LRUCacheSharded.start_link(name: n1, num_shards: 2, max_size: -3)

    assert m1 =~ ":max_size"
    assert m1 =~ "-3"

    n2 = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{message: m2}, _stack}} =
             LRUCacheSharded.start_link(name: n2, num_shards: 2, max_size: :lots)

    assert m2 =~ ":max_size"
    assert m2 =~ ":lots"
  end

  test "a missing required option fails loudly instead of defaulting" do
    Process.flag(:trap_exit, true)
    name = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%KeyError{key: :max_size}, _stack}} =
             LRUCacheSharded.start_link(name: name, num_shards: 2)

    assert {:error, {%KeyError{key: :num_shards}, _stack}} =
             LRUCacheSharded.start_link(name: :"#{name}_b", max_size: 4)

    assert_raise KeyError, fn ->
      LRUCacheSharded.start_link(num_shards: 2, max_size: 4)
    end
  end

  test "child_spec carries the documented id, type, restart and shutdown" do
    opts = [name: :child_spec_probe, num_shards: 2, max_size: 3]
    spec = LRUCacheSharded.child_spec(opts)

    assert %{id: :child_spec_probe, type: :worker, restart: :permanent, shutdown: 5_000} = spec
    assert {LRUCacheSharded, :start_link, [passed]} = spec.start
    assert passed[:num_shards] == 2
    assert passed[:max_size] == 3
  end

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

  # -------------------------------------------------------
  # put/3 return value
  # -------------------------------------------------------

  test "put returns the bare atom :ok for new keys, updates and evicting inserts" do
    c = start_cache(1, 2)

    # brand new key in an empty shard
    assert :ok = LRUCacheSharded.put(c, :a, 1)
    assert :ok = LRUCacheSharded.put(c, :b, 2)

    # in-place update of an existing key while the shard is exactly full
    assert :ok = LRUCacheSharded.put(c, :a, 99)

    # new key into a full shard, i.e. the insert that evicts the LRU entry
    assert :ok = LRUCacheSharded.put(c, :c, 3)

    # re-inserting an evicted key is a plain new insert again
    assert :ok = LRUCacheSharded.put(c, :b, 22)
  end

  # -------------------------------------------------------
  # Owner is off the hot path
  # -------------------------------------------------------

  test "get, put, size, num_shards and shard_index work while the owner cannot reply" do
    c = start_cache(4, 10)
    assert :ok = LRUCacheSharded.put(c, :parked, :v0)

    # Routing comes from the routing ETS table, not from a call into the
    # owner, so every public function keeps serving while the owner is
    # suspended and therefore unable to answer any call.
    :sys.suspend(c)

    try do
      assert LRUCacheSharded.num_shards(c) == 4

      idx = LRUCacheSharded.shard_index(c, :parked)
      assert idx >= 0 and idx < 4
      assert LRUCacheSharded.shard_index(c, :parked) == idx

      assert :ok = LRUCacheSharded.put(c, :during, :v1)
      assert {:ok, :v1} = LRUCacheSharded.get(c, :during)
      assert {:ok, :v0} = LRUCacheSharded.get(c, :parked)
      assert :miss = LRUCacheSharded.get(c, :absent)
      assert LRUCacheSharded.size(c) == 2
    after
      :sys.resume(c)
    end

    # and the cache is unchanged once the owner is answering again
    assert {:ok, :v1} = LRUCacheSharded.get(c, :during)
    assert LRUCacheSharded.size(c) == 2
  end
end
```

Send back the implementation only — one file, no tests.
