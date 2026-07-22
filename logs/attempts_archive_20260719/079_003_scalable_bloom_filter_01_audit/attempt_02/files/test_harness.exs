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
    # `add/2` skips anything `member?/2` reports as present, so a false positive
    # legitimately suppresses an insert. To assert an exact count we pick a
    # target rate low enough that a false positive across these 200 inserts is
    # vanishingly unlikely (compound bound P = 1.0e-9 => ~2.0e-7 expected).
    filter = ScalableBloomFilter.new(50, 1.0e-9)

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

  test "add/2 leaves the filter untouched for an item member?/2 already reports present" do
    filter = ScalableBloomFilter.new(50, 0.5)

    filter =
      Enum.reduce(1..50, filter, fn i, f ->
        ScalableBloomFilter.add(f, "seed-#{i}")
      end)

    fp_index =
      Enum.find(1..50_000, fn i ->
        ScalableBloomFilter.member?(filter, "absent-#{i}")
      end)

    assert fp_index, "expected to observe at least one false positive at rate 0.5"

    fp_item = "absent-#{fp_index}"
    assert ScalableBloomFilter.member?(filter, fp_item)

    count_before = ScalableBloomFilter.count(filter)
    slices_before = ScalableBloomFilter.num_slices(filter)

    updated = ScalableBloomFilter.add(filter, fp_item)

    assert ScalableBloomFilter.count(updated) == count_before
    assert ScalableBloomFilter.num_slices(updated) == slices_before
    assert updated == filter, "add/2 must return an already-member filter unchanged"
  end

  test "the second slice appears exactly when the first slice reaches initial_capacity" do
    filter = ScalableBloomFilter.new(4, 0.01)

    filter =
      Enum.reduce(1..3, filter, fn i, f ->
        ScalableBloomFilter.add(f, "b-#{i}")
      end)

    assert ScalableBloomFilter.num_slices(filter) == 1,
           "expected no growth while the active slice is below capacity"

    filter = ScalableBloomFilter.add(filter, "b-4")

    assert ScalableBloomFilter.count(filter) == 4
    assert ScalableBloomFilter.num_slices(filter) == 2
  end

  test "slice one holds twice the initial capacity before a third slice is appended" do
    filter = ScalableBloomFilter.new(4, 0.01)

    filter =
      Enum.reduce(1..11, filter, fn i, f ->
        ScalableBloomFilter.add(f, "g-#{i}")
      end)

    assert ScalableBloomFilter.num_slices(filter) == 2,
           "slice 1 has capacity 8; it must not be full after 7 of its items"

    filter = ScalableBloomFilter.add(filter, "g-12")

    assert ScalableBloomFilter.count(filter) == 12
    assert ScalableBloomFilter.num_slices(filter) == 3
  end

  test "member?/2 has no false negatives for nil, booleans, floats, lists and maps" do
    items = [nil, false, true, 3.14, -0.0, [], [1, [2, :b]], %{a: 1, b: %{c: 2}}, {}, "", :""]

    filter =
      Enum.reduce(items, ScalableBloomFilter.new(3, 0.01), &ScalableBloomFilter.add(&2, &1))

    assert ScalableBloomFilter.count(filter) == length(items)

    for item <- items do
      assert ScalableBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member"
    end
  end
end
