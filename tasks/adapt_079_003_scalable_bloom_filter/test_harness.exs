defmodule ScalableBloomFilterTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/2 starts with exactly one slice and zero count" do
    filter = ScalableBloomFilter.new(100, 0.01)
    assert ScalableBloomFilter.num_slices(filter) == 1
    assert ScalableBloomFilter.count(filter) == 0
  end

  # -------------------------------------------------------
  # Growth
  # -------------------------------------------------------

  test "filter grows new slices as capacity is exceeded" do
    filter = ScalableBloomFilter.new(100, 0.01)

    filter =
      Enum.reduce(1..500, filter, fn i, f ->
        ScalableBloomFilter.add(f, "item-#{i}")
      end)

    assert ScalableBloomFilter.num_slices(filter) > 1,
           "expected the filter to have grown beyond one slice"
  end

  test "small workloads do not grow past the first slice" do
    filter = ScalableBloomFilter.new(1_000, 0.01)

    filter =
      Enum.reduce(1..50, filter, fn i, f ->
        ScalableBloomFilter.add(f, "x-#{i}")
      end)

    assert ScalableBloomFilter.num_slices(filter) == 1
  end

  # -------------------------------------------------------
  # No false negatives (across slices)
  # -------------------------------------------------------

  test "member?/2 true for every added item, even after growth" do
    filter = ScalableBloomFilter.new(100, 0.01)
    items = for i <- 1..1_000, do: "member-#{i}"

    filter = Enum.reduce(items, filter, &ScalableBloomFilter.add(&2, &1))

    for item <- items do
      assert ScalableBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member after growth"
    end
  end

  test "mixed term types survive growth without false negatives" do
    filter = ScalableBloomFilter.new(5, 0.01)
    items = [:a, :b, 1, 2, 3, {:x, 1}, {:y, 2}, "s1", "s2", "s3"]

    filter = Enum.reduce(items, filter, &ScalableBloomFilter.add(&2, &1))

    for item <- items do
      assert ScalableBloomFilter.member?(filter, item)
    end
  end

  # -------------------------------------------------------
  # Count / dedup
  # -------------------------------------------------------

  test "adding a duplicate does not change count or grow the filter" do
    filter =
      ScalableBloomFilter.new(100, 0.01)
      |> ScalableBloomFilter.add("dup")

    slices_before = ScalableBloomFilter.num_slices(filter)
    filter = ScalableBloomFilter.add(filter, "dup")

    assert ScalableBloomFilter.count(filter) == 1
    assert ScalableBloomFilter.num_slices(filter) == slices_before
  end

  test "count tracks distinct insertions" do
    filter = ScalableBloomFilter.new(50, 0.01)

    filter =
      Enum.reduce(1..200, filter, fn i, f ->
        ScalableBloomFilter.add(f, "d-#{i}")
      end)

    assert ScalableBloomFilter.count(filter) == 200
  end

  # -------------------------------------------------------
  # Empty
  # -------------------------------------------------------

  test "empty filter reports no members" do
    filter = ScalableBloomFilter.new(100, 0.01)
    refute ScalableBloomFilter.member?(filter, "ghost")
    refute ScalableBloomFilter.member?(filter, 123)
  end

  # -------------------------------------------------------
  # Bounded false positive rate under growth
  # -------------------------------------------------------

  test "compound false positive rate stays bounded as the filter scales" do
    initial = 100
    p = 0.02
    filter = ScalableBloomFilter.new(initial, p)

    # Insert well beyond the initial capacity to force several slices.
    n = 300

    filter =
      Enum.reduce(1..n, filter, fn i, f ->
        ScalableBloomFilter.add(f, "present-#{i}")
      end)

    assert ScalableBloomFilter.num_slices(filter) > 1

    trials = 1_000

    false_positives =
      Enum.count(1..trials, fn i ->
        ScalableBloomFilter.member?(filter, "absent-#{i}")
      end)

    observed = false_positives / trials

    assert observed < p * 3,
           "compound false positive rate #{observed} exceeded bound #{p * 3}"
  end
end
