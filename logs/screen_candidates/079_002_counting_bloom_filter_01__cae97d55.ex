defmodule CountingBloomFilter do
  @moduledoc """
  A counting Bloom filter: a probabilistic set-membership structure that supports
  insertion, deletion and membership testing.

  Unlike a classic Bloom filter — which stores a single bit per slot and therefore
  cannot support removal — a counting Bloom filter stores a small integer counter
  per slot. Adding an item increments the `k` counters it hashes to; removing an
  item decrements them. An item is considered a member while all `k` of its
  counters are greater than zero.

  ## Sizing

  The counter-array size `m` and the number of hash functions `k` are derived from
  the expected number of live items `n` and the desired false-positive rate `p`
  using the standard Bloom filter formulas:

      m = -ceil(n * ln(p) / (ln 2)^2)
      k = round(m / n * ln 2)

  ## Counters

  Each counter is an integer in `0..255` and saturates at 255. A counter that has
  saturated has lost information: it is no longer known how many items map to it.
  To preserve the no-false-negatives guarantee, saturated counters are never
  decremented — they are "sticky" for the lifetime of the filter. This may cause
  additional false positives but never a false negative.

  ## Guarantees

    * `member?/2` never returns `false` for an item currently in the set.
    * `member?/2` may return `true` for an item that was never added
      (a false positive).

  ## Example

      iex> filter = CountingBloomFilter.new(1_000, 0.01)
      iex> filter = CountingBloomFilter.add(filter, :hello)
      iex> CountingBloomFilter.member?(filter, :hello)
      true
      iex> CountingBloomFilter.count(filter)
      1
      iex> filter = CountingBloomFilter.remove(filter, :hello)
      iex> CountingBloomFilter.member?(filter, :hello)
      false

  """

  defstruct [:m, :k, :counters, :size]

  @max_counter 255

  @typedoc "A counting Bloom filter."
  @type t :: %__MODULE__{
          m: pos_integer(),
          k: pos_integer(),
          counters: tuple(),
          size: non_neg_integer()
        }

  @ln2 0.6931471805599453
  @ln2_squared 0.4804530139182014

  @doc """
  Creates a new counting Bloom filter.

  `expected_size` is the anticipated number of live items (a positive integer) and
  `false_positive_rate` is the desired false-positive probability, a float strictly
  between `0.0` and `1.0`. The optimal counter-array size `m` and hash-function
  count `k` are derived from these two parameters.

  ## Examples

      iex> filter = CountingBloomFilter.new(100, 0.01)
      iex> CountingBloomFilter.count(filter)
      0

  """
  @spec new(pos_integer(), float()) :: t()
  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = optimal_m(expected_size, false_positive_rate)
    k = optimal_k(m, expected_size)

    %__MODULE__{
      m: m,
      k: k,
      counters: Tuple.duplicate(0, m),
      size: 0
    }
  end

  @doc """
  Adds `item` to the filter, returning the updated filter.

  Every one of the item's `k` counters is incremented, saturating at 255. Adding
  the same item twice is a multiset insert: its counters go to 2 and `count/1`
  reports 2. `item` may be any Elixir term.

  ## Examples

      iex> filter = CountingBloomFilter.new(100, 0.01)
      iex> filter = CountingBloomFilter.add(filter, "apple")
      iex> CountingBloomFilter.member?(filter, "apple")
      true

  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{counters: counters} = filter, item) do
    counters =
      filter
      |> indexes(item)
      |> Enum.reduce(counters, fn index, acc ->
        put_elem(acc, index, min(elem(acc, index) + 1, @max_counter))
      end)

    %__MODULE__{filter | counters: counters, size: filter.size + 1}
  end

  @doc """
  Removes `item` from the filter, returning the updated filter.

  If the item is not currently a member, the filter is returned unchanged.
  Otherwise each of the item's `k` counters is decremented (never below zero) and
  the live-item count is decremented.

  Counters that have saturated at 255 are never decremented, since a saturated
  counter no longer tracks how many items map to it; decrementing it could
  introduce a false negative.

  ## Examples

      iex> filter = CountingBloomFilter.new(100, 0.01)
      iex> filter = CountingBloomFilter.add(filter, "apple")
      iex> filter = CountingBloomFilter.remove(filter, "apple")
      iex> CountingBloomFilter.member?(filter, "apple")
      false

      iex> filter = CountingBloomFilter.new(100, 0.01)
      iex> CountingBloomFilter.remove(filter, "never added") == filter
      true

  """
  @spec remove(t(), term()) :: t()
  def remove(%__MODULE__{counters: counters} = filter, item) do
    indexes = indexes(filter, item)

    if member_at?(counters, indexes) do
      counters =
        Enum.reduce(indexes, counters, fn index, acc ->
          put_elem(acc, index, decrement(elem(acc, index)))
        end)

      %__MODULE__{filter | counters: counters, size: max(filter.size - 1, 0)}
    else
      filter
    end
  end

  @doc """
  Returns `true` if `item` may be a member of the filter, `false` if it is
  definitely not.

  An item is a member while all `k` of its counters are greater than zero. This
  never returns `false` for an item currently in the set, but may return `true`
  for an item that was never added.

  ## Examples

      iex> filter = CountingBloomFilter.new(100, 0.01)
      iex> CountingBloomFilter.member?(filter, "apple")
      false

  """
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{counters: counters} = filter, item) do
    member_at?(counters, indexes(filter, item))
  end

  @doc """
  Returns the number of live items in the filter.

  This is an exact running tally of successful `add/2` and `remove/2` operations,
  not an estimate derived from the counters.

  ## Examples

      iex> filter = CountingBloomFilter.new(100, 0.01)
      iex> filter = CountingBloomFilter.add(filter, :a)
      iex> filter = CountingBloomFilter.add(filter, :b)
      iex> CountingBloomFilter.count(filter)
      2

  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{size: size}), do: size

  @doc """
  Merges two filters by summing their counter arrays element-wise and summing
  their sizes.

  Counter sums saturate at 255. Both filters must have been created with identical
  `m` and `k` values.

  Raises `ArgumentError` if the filters are not compatible.

  ## Examples

      iex> a = CountingBloomFilter.add(CountingBloomFilter.new(100, 0.01), :a)
      iex> b = CountingBloomFilter.add(CountingBloomFilter.new(100, 0.01), :b)
      iex> merged = CountingBloomFilter.merge(a, b)
      iex> {CountingBloomFilter.member?(merged, :a), CountingBloomFilter.member?(merged, :b)}
      {true, true}

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{m: m, k: k} = filter1, %__MODULE__{m: m, k: k} = filter2) do
    counters =
      Enum.reduce(0..(m - 1)//1, filter1.counters, fn index, acc ->
        sum = elem(acc, index) + elem(filter2.counters, index)
        put_elem(acc, index, min(sum, @max_counter))
      end)

    %__MODULE__{filter1 | counters: counters, size: filter1.size + filter2.size}
  end

  def merge(%__MODULE__{} = filter1, %__MODULE__{} = filter2) do
    raise ArgumentError,
          "cannot merge counting Bloom filters with different parameters: " <>
            "{m: #{filter1.m}, k: #{filter1.k}} vs {m: #{filter2.m}, k: #{filter2.k}}"
  end

  # -- Internals --------------------------------------------------------------

  @spec optimal_m(pos_integer(), float()) :: pos_integer()
  defp optimal_m(n, p) do
    m = -ceil(n * :math.log(p) / @ln2_squared)
    max(m, 1)
  end

  @spec optimal_k(pos_integer(), pos_integer()) :: pos_integer()
  defp optimal_k(m, n) do
    k = round(m / n * @ln2)
    max(k, 1)
  end

  @spec indexes(t(), term()) :: [non_neg_integer()]
  defp indexes(%__MODULE__{m: m, k: k}, item) do
    Enum.map(0..(k - 1)//1, fn index -> :erlang.phash2({index, item}, m) end)
  end

  @spec member_at?(tuple(), [non_neg_integer()]) :: boolean()
  defp member_at?(counters, indexes) do
    Enum.all?(indexes, fn index -> elem(counters, index) > 0 end)
  end

  @spec decrement(0..255) :: 0..255
  defp decrement(@max_counter), do: @max_counter
  defp decrement(counter), do: max(counter - 1, 0)
end