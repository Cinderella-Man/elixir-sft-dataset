defmodule BloomFilterTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/2 produces a struct with computed m and k" do
    filter = BloomFilter.new(1_000, 0.01)

    # Optimal m for n=1000, p=0.01 is ~9585 bits; k is ~7
    assert filter.m > 0
    assert filter.k > 0

    # Sanity: tighter false-positive rate → larger bit array
    loose = BloomFilter.new(1_000, 0.10)
    tight = BloomFilter.new(1_000, 0.01)
    assert tight.m > loose.m
  end

  test "new/2 with different expected sizes scales m accordingly" do
    small = BloomFilter.new(100, 0.01)
    large = BloomFilter.new(10_000, 0.01)
    assert large.m > small.m
  end

  # -------------------------------------------------------
  # No false negatives
  # -------------------------------------------------------

  test "member?/2 always returns true for added items (no false negatives)" do
    filter = BloomFilter.new(500, 0.01)

    items = for i <- 1..500, do: "item-#{i}"
    filter = Enum.reduce(items, filter, &BloomFilter.add(&2, &1))

    for item <- items do
      assert BloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member but got false"
    end
  end

  test "atoms, integers, and tuples are never false-negatives" do
    filter = BloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    filter = Enum.reduce(items, filter, &BloomFilter.add(&2, &1))

    for item <- items do
      assert BloomFilter.member?(filter, item)
    end
  end

  # -------------------------------------------------------
  # False positive rate
  # -------------------------------------------------------

  test "false positive rate stays near the configured value" do
    n = 1_000
    p = 0.03
    filter = BloomFilter.new(n, p)

    # Add n distinct items
    filter =
      Enum.reduce(1..n, filter, fn i, f ->
        BloomFilter.add(f, "present-#{i}")
      end)

    # Test n absent items and count false positives
    false_positives =
      Enum.count(1..n, fn i ->
        BloomFilter.member?(filter, "absent-#{i}")
      end)

    observed_rate = false_positives / n

    # Allow 2× headroom around the configured rate
    assert observed_rate < p * 2,
           "False positive rate #{observed_rate} exceeded 2× target #{p}"
  end

  # -------------------------------------------------------
  # Empty filter
  # -------------------------------------------------------

  test "empty filter reports no members" do
    filter = BloomFilter.new(100, 0.01)

    refute BloomFilter.member?(filter, "ghost")
    refute BloomFilter.member?(filter, 0)
    refute BloomFilter.member?(filter, :nope)
  end

  # -------------------------------------------------------
  # Merge
  # -------------------------------------------------------

  test "merge/2 contains all items from both filters" do
    f1 = BloomFilter.new(200, 0.01)
    f2 = BloomFilter.new(200, 0.01)

    f1 = Enum.reduce(1..100, f1, fn i, f -> BloomFilter.add(f, "a-#{i}") end)
    f2 = Enum.reduce(1..100, f2, fn i, f -> BloomFilter.add(f, "b-#{i}") end)

    merged = BloomFilter.merge(f1, f2)

    for i <- 1..100 do
      assert BloomFilter.member?(merged, "a-#{i}")
      assert BloomFilter.member?(merged, "b-#{i}")
    end
  end

  test "merge/2 raises ArgumentError when filters have different parameters" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(999, 0.05)

    assert_raise ArgumentError, fn ->
      BloomFilter.merge(f1, f2)
    end
  end

  test "merge/2 with an empty filter leaves the other unchanged" do
    f1 = BloomFilter.new(100, 0.01)
    empty = BloomFilter.new(100, 0.01)

    f1 = Enum.reduce(["x", "y", "z"], f1, &BloomFilter.add(&2, &1))
    merged = BloomFilter.merge(f1, empty)

    assert BloomFilter.member?(merged, "x")
    assert BloomFilter.member?(merged, "y")
    assert BloomFilter.member?(merged, "z")
  end

  test "merge/2 is commutative" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(100, 0.01)

    f1 = BloomFilter.add(f1, "only-in-f1")
    f2 = BloomFilter.add(f2, "only-in-f2")

    m1 = BloomFilter.merge(f1, f2)
    m2 = BloomFilter.merge(f2, f1)

    assert BloomFilter.member?(m1, "only-in-f1")
    assert BloomFilter.member?(m1, "only-in-f2")
    assert BloomFilter.member?(m2, "only-in-f1")
    assert BloomFilter.member?(m2, "only-in-f2")

    # Bit arrays should be identical
    assert m1.bits == m2.bits
  end

  # -------------------------------------------------------
  # Idempotency
  # -------------------------------------------------------

  test "adding the same item multiple times has no extra effect" do
    f = BloomFilter.new(10, 0.01)
    f1 = BloomFilter.add(f, "dup")
    f2 = BloomFilter.add(f1, "dup")

    assert f1.bits == f2.bits
    assert BloomFilter.member?(f2, "dup")
  end
end
