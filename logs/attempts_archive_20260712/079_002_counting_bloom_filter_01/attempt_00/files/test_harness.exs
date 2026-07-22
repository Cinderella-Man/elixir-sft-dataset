defmodule CountingBloomFilterTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/2 produces a struct with computed m and k and zero size" do
    filter = CountingBloomFilter.new(1_000, 0.01)

    assert filter.m > 0
    assert filter.k > 0
    assert CountingBloomFilter.count(filter) == 0

    loose = CountingBloomFilter.new(1_000, 0.10)
    tight = CountingBloomFilter.new(1_000, 0.01)
    assert tight.m > loose.m
  end

  test "new/2 scales m with expected size" do
    small = CountingBloomFilter.new(100, 0.01)
    large = CountingBloomFilter.new(10_000, 0.01)
    assert large.m > small.m
  end

  # -------------------------------------------------------
  # No false negatives
  # -------------------------------------------------------

  test "member?/2 always true for added items (no false negatives)" do
    filter = CountingBloomFilter.new(500, 0.01)
    items = for i <- 1..500, do: "item-#{i}"
    filter = Enum.reduce(items, filter, &CountingBloomFilter.add(&2, &1))

    for item <- items do
      assert CountingBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member"
    end
  end

  test "mixed term types are never false-negatives" do
    filter = CountingBloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    filter = Enum.reduce(items, filter, &CountingBloomFilter.add(&2, &1))

    for item <- items do
      assert CountingBloomFilter.member?(filter, item)
    end
  end

  # -------------------------------------------------------
  # Deletion
  # -------------------------------------------------------

  test "remove/2 makes an isolated item a non-member" do
    filter =
      CountingBloomFilter.new(100, 0.01)
      |> CountingBloomFilter.add("solo")

    assert CountingBloomFilter.member?(filter, "solo")
    filter = CountingBloomFilter.remove(filter, "solo")
    refute CountingBloomFilter.member?(filter, "solo")
  end

  test "remove/2 respects multiset semantics" do
    filter =
      CountingBloomFilter.new(100, 0.01)
      |> CountingBloomFilter.add("dup")
      |> CountingBloomFilter.add("dup")

    assert CountingBloomFilter.count(filter) == 2

    filter = CountingBloomFilter.remove(filter, "dup")
    assert CountingBloomFilter.member?(filter, "dup")
    assert CountingBloomFilter.count(filter) == 1

    filter = CountingBloomFilter.remove(filter, "dup")
    refute CountingBloomFilter.member?(filter, "dup")
    assert CountingBloomFilter.count(filter) == 0
  end

  test "removing an item does not evict others sharing the set" do
    filter =
      CountingBloomFilter.new(200, 0.01)
      |> CountingBloomFilter.add("keep-a")
      |> CountingBloomFilter.add("keep-b")
      |> CountingBloomFilter.add("gone")

    filter = CountingBloomFilter.remove(filter, "gone")

    assert CountingBloomFilter.member?(filter, "keep-a")
    assert CountingBloomFilter.member?(filter, "keep-b")
  end

  test "remove/2 on a non-member is a no-op" do
    filter =
      CountingBloomFilter.new(100, 0.01)
      |> CountingBloomFilter.add("present")

    before_counters = filter.counters
    before_size = CountingBloomFilter.count(filter)

    filter = CountingBloomFilter.remove(filter, "absent")

    assert filter.counters == before_counters
    assert CountingBloomFilter.count(filter) == before_size
  end

  test "counters never go below zero" do
    filter =
      CountingBloomFilter.new(50, 0.01)
      |> CountingBloomFilter.add("x")

    filter = CountingBloomFilter.remove(filter, "x")
    # Removing again (now a non-member) must not underflow anything.
    filter = CountingBloomFilter.remove(filter, "x")

    for c <- Tuple.to_list(filter.counters) do
      assert c >= 0
    end
  end

  # -------------------------------------------------------
  # Count tracking
  # -------------------------------------------------------

  test "count/1 tracks live inserts and deletes" do
    filter = CountingBloomFilter.new(100, 0.01)
    assert CountingBloomFilter.count(filter) == 0

    filter =
      Enum.reduce(1..10, filter, fn i, f -> CountingBloomFilter.add(f, "n-#{i}") end)

    assert CountingBloomFilter.count(filter) == 10

    filter = CountingBloomFilter.remove(filter, "n-1")
    assert CountingBloomFilter.count(filter) == 9
  end

  # -------------------------------------------------------
  # False positive rate
  # -------------------------------------------------------

  test "false positive rate stays near the configured value" do
    n = 1_000
    p = 0.03
    filter = CountingBloomFilter.new(n, p)

    filter =
      Enum.reduce(1..n, filter, fn i, f -> CountingBloomFilter.add(f, "present-#{i}") end)

    false_positives =
      Enum.count(1..n, fn i -> CountingBloomFilter.member?(filter, "absent-#{i}") end)

    observed_rate = false_positives / n
    assert observed_rate < p * 2,
           "False positive rate #{observed_rate} exceeded 2x target #{p}"
  end

  # -------------------------------------------------------
  # Empty filter
  # -------------------------------------------------------

  test "empty filter reports no members" do
    filter = CountingBloomFilter.new(100, 0.01)
    refute CountingBloomFilter.member?(filter, "ghost")
    refute CountingBloomFilter.member?(filter, 0)
    refute CountingBloomFilter.member?(filter, :nope)
  end

  # -------------------------------------------------------
  # Merge
  # -------------------------------------------------------

  test "merge/2 contains all items from both filters and sums sizes" do
    f1 = CountingBloomFilter.new(200, 0.01)
    f2 = CountingBloomFilter.new(200, 0.01)

    f1 = Enum.reduce(1..100, f1, fn i, f -> CountingBloomFilter.add(f, "a-#{i}") end)
    f2 = Enum.reduce(1..100, f2, fn i, f -> CountingBloomFilter.add(f, "b-#{i}") end)

    merged = CountingBloomFilter.merge(f1, f2)

    for i <- 1..100 do
      assert CountingBloomFilter.member?(merged, "a-#{i}")
      assert CountingBloomFilter.member?(merged, "b-#{i}")
    end

    assert CountingBloomFilter.count(merged) == 200
  end

  test "merge/2 raises when parameters differ" do
    f1 = CountingBloomFilter.new(100, 0.01)
    f2 = CountingBloomFilter.new(999, 0.05)

    assert_raise ArgumentError, fn -> CountingBloomFilter.merge(f1, f2) end
  end

  test "merge/2 is commutative in membership" do
    f1 = CountingBloomFilter.new(100, 0.01) |> CountingBloomFilter.add("only-1")
    f2 = CountingBloomFilter.new(100, 0.01) |> CountingBloomFilter.add("only-2")

    m1 = CountingBloomFilter.merge(f1, f2)
    m2 = CountingBloomFilter.merge(f2, f1)

    assert m1.counters == m2.counters
    assert CountingBloomFilter.member?(m1, "only-1")
    assert CountingBloomFilter.member?(m2, "only-2")
  end
end