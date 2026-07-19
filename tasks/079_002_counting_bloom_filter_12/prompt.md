# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `new` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `CountingBloomFilter` that implements a **counting** Bloom filter — a probabilistic set-membership structure that, unlike a classic Bloom filter, also supports **deletion**.

Instead of a bit array, a counting Bloom filter keeps an array of small integer **counters**. Adding an item increments its `k` counters; removing an item decrements them. An item is considered a member while all `k` of its counters are greater than zero.

I need these functions in the public API:

- `CountingBloomFilter.new(expected_size, false_positive_rate)` — creates a new filter. It must automatically calculate the optimal counter-array size (`m`) and number of hash functions (`k`) from the two parameters, using the same formulas as a standard Bloom filter (`m = -ceil(n * ln p / (ln 2)^2)`, `k = round(m/n * ln 2)`). `expected_size` is the anticipated number of live items; `false_positive_rate` is a float strictly between 0.0 and 1.0. Store `m`, `k`, the counter array, and a running `size` (number of live items) in a struct defined exactly as `defstruct [:m, :k, :counters, :size]`, where `:counters` holds the `m` counters as a **tuple** (each counter an integer `0..255`).
- `CountingBloomFilter.add(filter, item)` — hashes the item with `k` derived hash functions and increments the corresponding counters, returning an updated filter. Counters saturate at 255 and must never overflow past it. Adding the same item twice is a multiset insert (its counters go to 2). Items can be any Elixir term.
- `CountingBloomFilter.remove(filter, item)` — if the item is currently a member, decrement its `k` counters (but never below zero) and decrement `size`; if it is not a member, return the filter unchanged. To preserve the no-false-negatives guarantee, a counter that has **saturated** at 255 must never be decremented.
- `CountingBloomFilter.member?(filter, item)` — returns `true` if all `k` counters for the item are greater than zero, else `false`. It must never return `false` for an item that is currently in the set (no false negatives), but may return `true` for items never added (false positives).
- `CountingBloomFilter.count(filter)` — returns the current number of live items (`size`).
- `CountingBloomFilter.merge(filter1, filter2)` — combines two filters by **summing** their counter arrays element-wise (saturating at 255) and summing their sizes. Both filters must have been created with identical `m` and `k` — raise `ArgumentError` otherwise.

For hashing, derive `k` independent hash functions from `:erlang.phash2/2` by hashing a `{index, item}` tuple. Stdlib only — no external dependencies. Give me the complete module in a single file.

## The module with `new` missing

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

  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    # TODO
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

Give me only the complete implementation of `new` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
