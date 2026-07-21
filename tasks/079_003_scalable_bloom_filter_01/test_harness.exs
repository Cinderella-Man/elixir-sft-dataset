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

  # Slice i holds initial_capacity * 2^i items, and a fresh slice is appended as
  # soon as the active slice's own item count reaches its capacity. With an
  # initial capacity of 100 the slice boundaries therefore fall at 100 and 300,
  # so 500 items occupy exactly three slices.
  test "slices open exactly at 100 and 300 items for an initial capacity of 100" do
    filter = ScalableBloomFilter.new(100, 0.01)

    f = add_seq(filter, 1..99, "g")
    assert ScalableBloomFilter.num_slices(f) == 1

    f = add_seq(f, 100..100, "g")
    assert ScalableBloomFilter.num_slices(f) == 2

    f = add_seq(f, 101..299, "g")
    assert ScalableBloomFilter.num_slices(f) == 2

    f = add_seq(f, 300..300, "g")
    assert ScalableBloomFilter.num_slices(f) == 3

    f = add_seq(f, 301..500, "g")
    assert ScalableBloomFilter.num_slices(f) == 3
    assert ScalableBloomFilter.count(f) == 500
  end

  # The growth factor is 2, so with an initial capacity of 1 the cumulative
  # capacity after i+1 slices is 2^(i+1) - 1: new slices appear at 1, 3, 7, 15
  # and 31 items.
  test "capacities double per slice: a capacity-1 filter grows at 1, 3, 7, 15, 31" do
    filter = ScalableBloomFilter.new(1, 0.01)
    milestones = [{1, 2}, {3, 3}, {7, 4}, {15, 5}, {31, 6}]

    Enum.reduce(milestones, {filter, 1}, fn {total, slices}, {f, next} ->
      f = add_seq(f, next..total, "p")

      assert ScalableBloomFilter.num_slices(f) == slices,
             "expected #{slices} slices once #{total} items had been added"

      {f, total + 1}
    end)
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

  # Duplicate detection is exact, so a term the probabilistic query wrongly
  # reports as present is still counted as a genuinely new insertion, and only
  # becomes a real duplicate once it has actually been added.
  test "a term the membership query falsely reports is still counted as new" do
    # A tiny, loosely tuned filter makes member?/2 report true for terms that
    # were never inserted.
    filter = add_seq(ScalableBloomFilter.new(4, 0.5), 1..3, "seed")

    ghost = find_false_positive(filter, "ghost", 20_000) || "never-added-term"
    before_count = ScalableBloomFilter.count(filter)

    grown = ScalableBloomFilter.add(filter, ghost)
    assert ScalableBloomFilter.count(grown) == before_count + 1
    assert ScalableBloomFilter.member?(grown, ghost)

    again = ScalableBloomFilter.add(grown, ghost)
    assert ScalableBloomFilter.count(again) == before_count + 1
  end

  # Even in a filter tuned so loosely that membership queries report present for
  # many unseen terms, every distinct term passed to add/2 is counted.
  test "count stays exact in a filter riddled with false positives" do
    filter = add_seq(ScalableBloomFilter.new(4, 0.5), 1..200, "exact")

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

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp add_seq(filter, range, prefix) do
    Enum.reduce(range, filter, fn i, f ->
      ScalableBloomFilter.add(f, "#{prefix}-#{i}")
    end)
  end

  # Returns a never-added term the membership query reports as present, or nil
  # when the scan finds none.
  defp find_false_positive(filter, prefix, limit) do
    Enum.find_value(1..limit, fn i ->
      candidate = "#{prefix}-#{i}"
      if ScalableBloomFilter.member?(filter, candidate), do: candidate
    end)
  end
end
