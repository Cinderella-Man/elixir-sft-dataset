defmodule LRUCacheTest do
  use ExUnit.Case, async: false

  # Helper: start a uniquely named cache per test to avoid collisions
  defp start_cache(max_size) do
    name = :"lru_#{System.unique_integer([:positive])}"
    start_supervised!({LRUCache, name: name, max_size: max_size})
    name
  end

  # -------------------------------------------------------
  # Basic get / put
  # -------------------------------------------------------

  test "get returns :miss for unknown key" do
    c = start_cache(3)
    assert :miss = LRUCache.get(c, :missing)
  end

  test "put and get round-trip" do
    c = start_cache(3)
    assert :ok = LRUCache.put(c, :a, 1)
    assert {:ok, 1} = LRUCache.get(c, :a)
  end

  test "put overwrites an existing key" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :a, 42)
    assert {:ok, 42} = LRUCache.get(c, :a)
  end

  test "multiple distinct keys coexist" do
    c = start_cache(5)
    for i <- 1..5, do: LRUCache.put(c, i, i * 10)

    for i <- 1..5 do
      expected = i * 10
      assert {:ok, ^expected} = LRUCache.get(c, i)
    end
  end

  # -------------------------------------------------------
  # Eviction — basic LRU order
  # -------------------------------------------------------

  test "oldest entry is evicted when cache exceeds max_size" do
    c = start_cache(3)
    # inserted first → LRU
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)
    # should evict :a
    LRUCache.put(c, :d, 4)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  test "filling beyond capacity evicts in insertion order" do
    c = start_cache(2)
    LRUCache.put(c, :x, 10)
    LRUCache.put(c, :y, 20)
    # evicts :x
    LRUCache.put(c, :z, 30)
    # evicts :y
    LRUCache.put(c, :w, 40)

    assert :miss = LRUCache.get(c, :x)
    assert :miss = LRUCache.get(c, :y)
    assert {:ok, 30} = LRUCache.get(c, :z)
    assert {:ok, 40} = LRUCache.get(c, :w)
  end

  # -------------------------------------------------------
  # get refreshes recency — prevents premature eviction
  # -------------------------------------------------------

  test "get saves an entry from eviction" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Touch :a so it becomes MRU; :b is now the LRU
    LRUCache.get(c, :a)

    # Adding :d should evict :b, not :a
    LRUCache.put(c, :d, 4)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  test "repeated gets keep pushing an entry to MRU position" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Keep touching :a
    LRUCache.get(c, :a)
    LRUCache.get(c, :a)

    # evicts :b (oldest untouched)
    LRUCache.put(c, :d, 4)
    # evicts :c
    LRUCache.put(c, :e, 5)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert :miss = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert {:ok, 5} = LRUCache.get(c, :e)
  end

  # -------------------------------------------------------
  # put on existing key refreshes recency
  # -------------------------------------------------------

  test "updating an existing key refreshes its recency" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Update :a — it should now be MRU; :b becomes LRU
    LRUCache.put(c, :a, 99)

    # should evict :b
    LRUCache.put(c, :d, 4)

    assert {:ok, 99} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  # -------------------------------------------------------
  # Max size of 1 — extreme edge case
  # -------------------------------------------------------

  test "cache of size 1 always holds only the latest entry" do
    c = start_cache(1)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)

    LRUCache.put(c, :c, 3)

    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
  end

  test "get on the sole entry in a size-1 cache still returns it" do
    c = start_cache(1)
    LRUCache.put(c, :only, :value)
    assert {:ok, :value} = LRUCache.get(c, :only)
    assert {:ok, :value} = LRUCache.get(c, :only)
  end

  # -------------------------------------------------------
  # Values: arbitrary terms
  # -------------------------------------------------------

  test "cache stores arbitrary Elixir terms as values" do
    c = start_cache(5)
    LRUCache.put(c, :list, [1, 2, 3])
    LRUCache.put(c, :map, %{a: 1})
    LRUCache.put(c, :tuple, {:ok, "hello"})
    LRUCache.put(c, nil, nil)

    assert {:ok, [1, 2, 3]} = LRUCache.get(c, :list)
    assert {:ok, %{a: 1}} = LRUCache.get(c, :map)
    assert {:ok, {:ok, "hello"}} = LRUCache.get(c, :tuple)
    assert {:ok, nil} = LRUCache.get(c, nil)
  end

  # -------------------------------------------------------
  # Multiple independent cache instances
  # -------------------------------------------------------

  test "two cache instances are fully independent" do
    c1 = start_cache(2)
    c2 = start_cache(2)

    LRUCache.put(c1, :a, :from_c1)
    LRUCache.put(c2, :a, :from_c2)

    assert {:ok, :from_c1} = LRUCache.get(c1, :a)
    assert {:ok, :from_c2} = LRUCache.get(c2, :a)

    # Evict from c1 only
    LRUCache.put(c1, :b, :b)
    # evicts :a from c1
    LRUCache.put(c1, :c, :c)

    assert :miss = LRUCache.get(c1, :a)
    assert {:ok, :from_c2} = LRUCache.get(c2, :a)
  end
end
