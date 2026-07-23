# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `optimal_m` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# Specification: `CountingBloomFilter` — A Deletable Probabilistic Set

## Overview

This document specifies an Elixir module named `CountingBloomFilter` that implements a **counting** Bloom filter: a probabilistic set-membership structure which, unlike a classic Bloom filter, also supports **deletion**.

Where a classic Bloom filter uses a bit array, a counting Bloom filter maintains an array of small integer **counters**. Adding an item increments its `k` counters; removing an item decrements them. An item is considered a member for as long as all `k` of its counters are greater than zero.

The structure is stored in a struct defined exactly as `defstruct [:m, :k, :counters, :size]`, holding the counter-array size `m`, the number of hash functions `k`, the counter array, and a running `size` (the number of live items). The `:counters` field holds the `m` counters as a **tuple**, each counter being an integer in `0..255`.

## API

The public API consists of the following functions.

### `CountingBloomFilter.new(expected_size, false_positive_rate)`

Creates a new filter. It must automatically calculate the optimal counter-array size (`m`) and number of hash functions (`k`) from the two parameters, using the same formulas as a standard Bloom filter:

- `m = -ceil(n * ln p / (ln 2)^2)`
- `k = round(m/n * ln 2)`

`expected_size` is the anticipated number of live items. `false_positive_rate` is a float strictly between 0.0 and 1.0.

### `CountingBloomFilter.add(filter, item)`

Hashes the item with `k` derived hash functions and increments the corresponding counters, returning an updated filter. Items may be any Elixir term.

### `CountingBloomFilter.remove(filter, item)`

If the item is currently a member, this decrements its `k` counters and decrements `size`. If it is not a member, the filter is returned unchanged.

### `CountingBloomFilter.member?(filter, item)`

Returns `true` if all `k` counters for the item are greater than zero, and `false` otherwise.

### `CountingBloomFilter.count(filter)`

Returns the current number of live items (`size`).

### `CountingBloomFilter.merge(filter1, filter2)`

Combines two filters by **summing** their counter arrays element-wise and summing their sizes.

## Hashing

The `k` independent hash functions are derived from `:erlang.phash2/2` by hashing a `{index, item}` tuple.

## Edge cases

- **Saturation on add.** Counters saturate at 255 and must never overflow past it.
- **Multiset insert.** Adding the same item twice is a multiset insert: its counters go to 2.
- **Floor on remove.** Decrementing must never take a counter below zero.
- **Saturated counters are frozen.** To preserve the no-false-negatives guarantee, a counter that has **saturated** at 255 must never be decremented.
- **Removing a non-member.** Such a call returns the filter unchanged.
- **Membership guarantees.** `CountingBloomFilter.member?/2` must never return `false` for an item that is currently in the set (no false negatives), but it may return `true` for items never added (false positives).
- **Merge saturation.** Element-wise counter sums saturate at 255.
- **Merge compatibility.** Both filters must have been created with identical `m` and `k`; otherwise `ArgumentError` must be raised.

## Deliverable

The complete module, in a single file. Stdlib only — no external dependencies.

## The module with `optimal_m` missing

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

  defp optimal_m(n, p) do
    # TODO
  end

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

Reply with `optimal_m` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
