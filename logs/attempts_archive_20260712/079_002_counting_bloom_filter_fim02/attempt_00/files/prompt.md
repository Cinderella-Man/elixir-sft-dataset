Implement the public `merge/2` function.

`merge(filter1, filter2)` combines two counting Bloom filters into a new one. It
must:

- Sum the two filters' counter arrays **element-wise**, saturating each summed
  counter at `255` (the `@max_count` cap) so no counter overflows past it.
- Sum the two filters' `size` fields to get the merged live-item count.
- Return an updated `%CountingBloomFilter{}` (based on `filter1`) carrying the
  merged counters and summed size.

The two filters must have been created with **identical** `m` and `k`. When they
match, produce the merged filter as above. When they differ, raise an
`ArgumentError` explaining the mismatch (include both filters' `m` and `k`
values in the message). Use pattern matching on the struct fields to distinguish
the compatible case from the incompatible one.

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
  def merge(%__MODULE__{} = filter1, %__MODULE__{} = filter2) do
    # TODO
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