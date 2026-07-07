# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule CountingBloomFilter do
  @moduledoc """
  A **counting** Bloom filter — a probabilistic set-membership structure that
  additionally supports deletion.

  A classic Bloom filter stores a single bit per slot and therefore cannot
  support removal (clearing a bit might evict other items). A counting Bloom
  filter stores a small integer counter per slot: `add/2` increments the `k`
  counters for an item, `remove/2` decrements them, and an item is a member
  while all `k` of its counters are non-zero.

  ## Example

      iex> f = CountingBloomFilter.new(1_000, 0.01)
      iex> f = CountingBloomFilter.add(f, "hello")
      iex> CountingBloomFilter.member?(f, "hello")
      true
      iex> f = CountingBloomFilter.remove(f, "hello")
      iex> CountingBloomFilter.member?(f, "hello")
      false

  Counters saturate at `255`. A saturated counter is never decremented, which
  preserves the no-false-negatives guarantee at the cost of leaving a few slots
  permanently set (the standard trade-off for counting Bloom filters).
  """

  @ln2 :math.log(2)
  @max_count 255

  @enforce_keys [:m, :k, :counters, :size]
  defstruct [:m, :k, :counters, :size]

  @type t :: %__MODULE__{
          m: pos_integer(),
          k: pos_integer(),
          counters: tuple(),
          size: non_neg_integer()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new, empty counting Bloom filter sized for `expected_size` live
  items at the given `false_positive_rate`.
  """
  @spec new(pos_integer(), float()) :: t()
  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = optimal_m(expected_size, false_positive_rate)
    k = optimal_k(m, expected_size)
    %__MODULE__{m: m, k: k, counters: Tuple.duplicate(0, m), size: 0}
  end

  @doc """
  Adds `item` (multiset insert) and returns the updated filter.
  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{m: m, k: k, counters: counters, size: size} = filter, item) do
    new_counters =
      Enum.reduce(0..(k - 1), counters, fn seed, acc ->
        increment(acc, hash(item, seed, m))
      end)

    %{filter | counters: new_counters, size: size + 1}
  end

  @doc """
  Removes `item` if it is currently a member; otherwise returns the filter
  unchanged. Counters never go below zero, and saturated counters are left
  untouched to avoid introducing false negatives.
  """
  @spec remove(t(), term()) :: t()
  def remove(%__MODULE__{m: m, k: k, counters: counters, size: size} = filter, item) do
    if member?(filter, item) do
      new_counters =
        Enum.reduce(0..(k - 1), counters, fn seed, acc ->
          decrement(acc, hash(item, seed, m))
        end)

      %{filter | counters: new_counters, size: max(0, size - 1)}
    else
      filter
    end
  end

  @doc """
  Returns `true` if `item` is (probably) a member — i.e. all `k` counters are
  greater than zero.
  """
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{m: m, k: k, counters: counters}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      elem(counters, hash(item, seed, m)) > 0
    end)
  end

  @doc "Returns the current number of live items."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{size: size}), do: size

  @doc """
  Merges two filters by summing counter arrays element-wise (saturating at 255)
  and summing sizes. Both filters must share `m` and `k`.
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{m: m, k: k} = f1, %__MODULE__{m: m, k: k} = f2) do
    merged =
      Tuple.to_list(f1.counters)
      |> Enum.zip(Tuple.to_list(f2.counters))
      |> Enum.map(fn {a, b} -> min(@max_count, a + b) end)
      |> List.to_tuple()

    %{f1 | counters: merged, size: f1.size + f2.size}
  end

  def merge(%__MODULE__{} = f1, %__MODULE__{} = f2) do
    raise ArgumentError,
          "cannot merge filters with different parameters: " <>
            "filter1 has m=#{f1.m}, k=#{f1.k}; filter2 has m=#{f2.m}, k=#{f2.k}"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp optimal_m(n, p), do: max(1, ceil(-n * :math.log(p) / (@ln2 * @ln2)))
  defp optimal_k(m, n), do: max(1, round(m / n * @ln2))

  defp hash(item, seed, m), do: :erlang.phash2({seed, item}, m)

  defp increment(counters, idx) do
    case elem(counters, idx) do
      v when v >= @max_count -> counters
      v -> put_elem(counters, idx, v + 1)
    end
  end

  defp decrement(counters, idx) do
    case elem(counters, idx) do
      0 -> counters
      v when v >= @max_count -> counters
      v -> put_elem(counters, idx, v - 1)
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule CountingBloomFilterTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/2 produces a struct with computed m and k and zero size" do
    # TODO
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
```
