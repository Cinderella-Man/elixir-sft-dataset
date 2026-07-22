Implement the private `decrement/2` helper for `CountingBloomFilter`.

`decrement(counters, idx)` takes the counter tuple and an index, and returns an
updated counter tuple with the counter at `idx` decreased by one — subject to two
guards that preserve the counting Bloom filter's invariants:

- If the counter at `idx` is `0`, leave it unchanged (counters must never go
  below zero).
- If the counter at `idx` is saturated (i.e. `>= @max_count`, which is `255`),
  leave it unchanged. A saturated counter has lost track of its true value, so
  decrementing it could introduce a false negative; it must stay pinned at 255.
- Otherwise, decrement the counter at `idx` by one using `put_elem/3` and return
  the updated tuple.

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
    # TODO
  end
end
```