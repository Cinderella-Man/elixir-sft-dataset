# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ScalableBloomFilter do
  @moduledoc """
  A **scalable** Bloom filter that grows automatically to keep the compound
  false-positive probability bounded even as the number of inserted items far
  exceeds the initial capacity guess.

  The structure is a list of ordinary Bloom-filter *slices*. Inserts go into
  the newest (active) slice; when it fills, a larger slice with a tighter
  per-slice error rate is appended. Membership is the OR of membership across
  every slice.

  Growth constants: capacity factor `s = 2`, tightening ratio `r = 0.5`. For a
  target rate `P`, the first slice uses `p0 = P * (1 - r)` and slice `i` uses
  rate `p0 * r^i` with capacity `initial_capacity * s^i`. This bounds the total
  false-positive probability by `p0 / (1 - r) = P`.

  Because a Bloom filter can report false positives, relying on `member?/2`
  alone to reject duplicates would occasionally drop genuinely new items (a
  false positive on an unseen item), corrupting the `count`. To keep the
  distinct-item count and duplicate-suppression exact, the filter also tracks
  the set of inserted terms; `member?/2` itself remains a true probabilistic
  Bloom-filter query over the slices.
  """

  @ln2 :math.log(2)
  @growth 2
  @ratio 0.5

  @enforce_keys [:capacity0, :p0, :slices, :count, :items]
  defstruct [:capacity0, :p0, :slices, :count, :items]

  @type slice :: %{
          m: pos_integer(),
          k: pos_integer(),
          bits: tuple(),
          capacity: pos_integer(),
          count: non_neg_integer()
        }

  @type t :: %__MODULE__{
          capacity0: pos_integer(),
          p0: float(),
          slices: [slice()],
          count: non_neg_integer(),
          items: MapSet.t()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Creates a scalable filter with a single empty slice."
  @spec new(pos_integer(), float()) :: t()
  def new(initial_capacity, false_positive_rate)
      when is_integer(initial_capacity) and initial_capacity > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    p0 = false_positive_rate * (1 - @ratio)
    first = make_slice(0, initial_capacity, p0)

    %__MODULE__{
      capacity0: initial_capacity,
      p0: p0,
      slices: [first],
      count: 0,
      items: MapSet.new()
    }
  end

  @doc """
  Adds `item`. Duplicates are ignored (no double-counting). When the active
  slice fills, a larger slice is appended for future inserts.
  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{} = filter, item) do
    if MapSet.member?(filter.items, item) do
      filter
    else
      [active | rest] = filter.slices

      active = %{
        active
        | bits: set_bits(active, item),
          count: active.count + 1
      }

      slices =
        if active.count >= active.capacity do
          index = length(filter.slices)
          fresh = make_slice(index, filter.capacity0, filter.p0)
          [fresh, active | rest]
        else
          [active | rest]
        end

      %{
        filter
        | slices: slices,
          count: filter.count + 1,
          items: MapSet.put(filter.items, item)
      }
    end
  end

  @doc "Returns `true` if `item` is present in any slice."
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{slices: slices}, item) do
    Enum.any?(slices, fn slice -> slice_member?(slice, item) end)
  end

  @doc "Total number of distinct items inserted."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{count: count}), do: count

  @doc "Current number of slices."
  @spec num_slices(t()) :: pos_integer()
  def num_slices(%__MODULE__{slices: slices}), do: length(slices)

  # ---------------------------------------------------------------------------
  # Slice construction and bit operations
  # ---------------------------------------------------------------------------

  defp make_slice(index, capacity0, p0) do
    p_i = p0 * :math.pow(@ratio, index)
    capacity = max(1, round(capacity0 * :math.pow(@growth, index)))
    m = max(1, ceil(-capacity * :math.log(p_i) / (@ln2 * @ln2)))
    k = max(1, round(m / capacity * @ln2))
    num_words = ceil(m / 64)

    %{m: m, k: k, bits: Tuple.duplicate(0, num_words), capacity: capacity, count: 0}
  end

  defp set_bits(%{m: m, k: k, bits: bits}, item) do
    Enum.reduce(0..(k - 1), bits, fn seed, acc ->
      set_bit(acc, hash(item, seed, m))
    end)
  end

  defp slice_member?(%{m: m, k: k, bits: bits}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      get_bit(bits, hash(item, seed, m)) == 1
    end)
  end

  defp hash(item, seed, m), do: :erlang.phash2({seed, item}, m)

  defp set_bit(bits, bit_index) do
    wi = div(bit_index, 64)
    bo = rem(bit_index, 64)
    put_elem(bits, wi, Bitwise.bor(elem(bits, wi), Bitwise.bsl(1, bo)))
  end

  defp get_bit(bits, bit_index) do
    wi = div(bit_index, 64)
    bo = rem(bit_index, 64)
    Bitwise.band(Bitwise.bsr(elem(bits, wi), bo), 1)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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
```
