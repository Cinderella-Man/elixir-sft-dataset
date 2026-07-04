defmodule WeightedLRUCacheTest do
  use ExUnit.Case, async: false

  defp start_cache(max_weight) do
    name = :"wlru_#{System.unique_integer([:positive])}"
    start_supervised!({WeightedLRUCache, name: name, max_weight: max_weight})
    name
  end

  # -------------------------------------------------------
  # Basic get / put and weight tracking
  # -------------------------------------------------------

  test "get returns :miss for unknown key" do
    c = start_cache(10)
    assert :miss = WeightedLRUCache.get(c, :nope)
  end

  test "put and get round-trip" do
    c = start_cache(10)
    assert :ok = WeightedLRUCache.put(c, :a, "val", 3)
    assert {:ok, "val"} = WeightedLRUCache.get(c, :a)
  end

  test "weight tracks the sum of resident entry weights" do
    c = start_cache(10)
    assert WeightedLRUCache.weight(c) == 0
    WeightedLRUCache.put(c, :a, 1, 3)
    WeightedLRUCache.put(c, :b, 2, 4)
    assert WeightedLRUCache.weight(c) == 7
  end

  # -------------------------------------------------------
  # Weight-based eviction
  # -------------------------------------------------------

  test "inserting evicts LRU entries until the newcomer fits" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 6)
    WeightedLRUCache.put(c, :b, "b", 3)
    # total 9; adding c(4) → 13 > 10 → evict LRU (:a, 6) → 3, +4 = 7 ≤ 10
    WeightedLRUCache.put(c, :c, "c", 4)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert {:ok, "b"} = WeightedLRUCache.get(c, :b)
    assert {:ok, "c"} = WeightedLRUCache.get(c, :c)
    assert WeightedLRUCache.weight(c) == 7
  end

  test "a single put may evict several entries in a row" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 4)
    WeightedLRUCache.put(c, :b, "b", 4)
    # total 8; adding big(9) → evict :a → 4, still 4+9>10 → evict :b → 0, +9 = 9
    WeightedLRUCache.put(c, :big, "big", 9)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert {:ok, "big"} = WeightedLRUCache.get(c, :big)
    assert WeightedLRUCache.weight(c) == 9
  end

  test "an entry that exactly fills the budget is allowed" do
    c = start_cache(10)
    assert :ok = WeightedLRUCache.put(c, :a, "a", 10)
    assert WeightedLRUCache.weight(c) == 10
    # next insert must evict :a to make room
    assert :ok = WeightedLRUCache.put(c, :b, "b", 1)
    assert :miss = WeightedLRUCache.get(c, :a)
    assert {:ok, "b"} = WeightedLRUCache.get(c, :b)
    assert WeightedLRUCache.weight(c) == 1
  end

  # -------------------------------------------------------
  # get refreshes recency
  # -------------------------------------------------------

  test "get saves an entry from weight eviction" do
    c = start_cache(6)
    WeightedLRUCache.put(c, :a, "a", 2)
    WeightedLRUCache.put(c, :b, "b", 2)
    WeightedLRUCache.put(c, :c, "c", 2)
    # touch :a → :b is now LRU
    WeightedLRUCache.get(c, :a)
    # adding d(2) → 6+2 > 6 → evict LRU (:b)
    WeightedLRUCache.put(c, :d, "d", 2)

    assert {:ok, "a"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert {:ok, "c"} = WeightedLRUCache.get(c, :c)
    assert {:ok, "d"} = WeightedLRUCache.get(c, :d)
    assert WeightedLRUCache.weight(c) == 6
  end

  # -------------------------------------------------------
  # Updating an existing key
  # -------------------------------------------------------

  test "updating a key replaces its value and adjusts total weight" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 5)
    assert WeightedLRUCache.weight(c) == 5
    WeightedLRUCache.put(c, :a, "a2", 2)
    assert {:ok, "a2"} = WeightedLRUCache.get(c, :a)
    assert WeightedLRUCache.weight(c) == 2
  end

  test "growing an existing key's weight can evict other entries" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 2)
    WeightedLRUCache.put(c, :b, "b", 2)
    # update :a to a big weight: release old 2 (total 2), then need room for 9
    WeightedLRUCache.put(c, :a, "a-big", 9)

    assert {:ok, "a-big"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert WeightedLRUCache.weight(c) == 9
  end

  # -------------------------------------------------------
  # Failure semantics
  # -------------------------------------------------------

  test "rejects an entry whose weight alone exceeds the budget without evicting" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 8)
    assert {:error, :too_large} = WeightedLRUCache.put(c, :big, "big", 11)

    # nothing evicted, nothing inserted
    assert {:ok, "a"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :big)
    assert WeightedLRUCache.weight(c) == 8
  end

  test "rejects a non-positive or non-integer weight" do
    c = start_cache(10)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :a, "a", 0)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :b, "b", -3)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :c, "c", 1.5)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert WeightedLRUCache.weight(c) == 0
  end

  # -------------------------------------------------------
  # Arbitrary terms + independence
  # -------------------------------------------------------

  test "stores arbitrary Elixir terms as values" do
    c = start_cache(20)
    WeightedLRUCache.put(c, :list, [1, 2, 3], 1)
    WeightedLRUCache.put(c, :map, %{a: 1}, 1)
    WeightedLRUCache.put(c, nil, nil, 1)

    assert {:ok, [1, 2, 3]} = WeightedLRUCache.get(c, :list)
    assert {:ok, %{a: 1}} = WeightedLRUCache.get(c, :map)
    assert {:ok, nil} = WeightedLRUCache.get(c, nil)
  end

  test "two cache instances are fully independent" do
    c1 = start_cache(5)
    c2 = start_cache(5)
    WeightedLRUCache.put(c1, :k, :from_c1, 2)
    WeightedLRUCache.put(c2, :k, :from_c2, 2)

    assert {:ok, :from_c1} = WeightedLRUCache.get(c1, :k)
    assert {:ok, :from_c2} = WeightedLRUCache.get(c2, :k)
  end
end