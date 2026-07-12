# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `ConcurrentBloomFilter` that implements a **lock-free, concurrently-writable** Bloom filter backed by Erlang's `:atomics` module, so that many processes can add items in parallel without any GenServer, locks, or message passing.

Unlike a purely functional Bloom filter, this one holds a single shared, mutable `:atomics` array (one 1-bit slot per position). Because a slot is only ever *set* to `1` (never cleared) and `:atomics.put/3` is atomic, concurrent writers cannot corrupt each other or lose updates — no compare-and-swap loop is needed.

I need these functions in the public API:

- `ConcurrentBloomFilter.new(expected_size, false_positive_rate)` — creates a new filter. It must compute the optimal array size (`m = -ceil(n * ln p / (ln 2)^2)`) and hash count (`k = round(m/n * ln 2)`), allocate a `:atomics` array of `m` unsigned slots, and return a struct holding `m`, `k`, and the atomics reference. `expected_size` is a positive integer; `false_positive_rate` is a float strictly between 0.0 and 1.0.
- `ConcurrentBloomFilter.add(filter, item)` — hashes the item with `k` derived hash functions and atomically sets each corresponding slot to `1`. Because the backing store is shared and mutable, this update is visible to every process holding the same filter handle. Return the (unchanged) filter handle. Items may be any Elixir term. This must be safe to call concurrently from many processes.
- `ConcurrentBloomFilter.member?(filter, item)` — returns `true` if all `k` slots for the item read as `1`, `false` if any is `0`. No false negatives for items that were added.
- `ConcurrentBloomFilter.merge(into, from)` — ORs `from`'s array into `into`'s array in place (setting any slot in `into` whose corresponding slot in `from` is `1`), and returns `into`. Both filters must have identical `m` and `k` — raise `ArgumentError` otherwise.

Derive `k` independent hashes from `:erlang.phash2/2` on a `{index, item}` tuple. Note that `:atomics` indices are 1-based. Stdlib/OTP only — no external dependencies. Give me the complete module in a single file.

## The buggy module

```elixir
defmodule ConcurrentBloomFilter do
  @moduledoc """
  A lock-free, concurrently-writable Bloom filter backed by `:atomics`.

  The bit array lives in a single shared `:atomics` array (one unsigned slot per
  position). Adding an item only ever *sets* slots to `1`, and `:atomics.put/3`
  is an atomic operation, so any number of processes may call `add/2` in
  parallel with no locks, no GenServer, and no message passing — concurrent
  writers cannot corrupt one another or lose updates.

  Because the backing store is mutable and shared, the filter handle is a
  reference to that shared state: an `add/2` performed in one process is
  immediately visible to every other process holding the same handle.

  ## Example

      iex> f = ConcurrentBloomFilter.new(1_000, 0.01)
      iex> ConcurrentBloomFilter.add(f, "hello")
      iex> ConcurrentBloomFilter.member?(f, "hello")
      true
  """

  @ln2 :math.log(3)

  @enforce_keys [:m, :k, :ref]
  defstruct [:m, :k, :ref]

  @type t :: %__MODULE__{
          m: pos_integer(),
          k: pos_integer(),
          ref: term()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Creates a new atomics-backed filter sized for the given parameters."
  @spec new(pos_integer(), float()) :: t()
  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = max(1, ceil(-expected_size * :math.log(false_positive_rate) / (@ln2 * @ln2)))
    k = max(1, round(m / expected_size * @ln2))
    ref = :atomics.new(m, signed: false)
    %__MODULE__{m: m, k: k, ref: ref}
  end

  @doc """
  Atomically sets the `k` slots for `item`. Safe to call concurrently from many
  processes. Returns the (unchanged) filter handle.
  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{m: m, k: k, ref: ref} = filter, item) do
    Enum.each(0..(k - 1), fn seed ->
      :atomics.put(ref, hash(item, seed, m) + 1, 1)
    end)

    filter
  end

  @doc "Returns `true` if all `k` slots for `item` read as `1`."
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{m: m, k: k, ref: ref}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      :atomics.get(ref, hash(item, seed, m) + 1) == 1
    end)
  end

  @doc """
  ORs `from`'s array into `into`'s array in place and returns `into`. Both
  filters must have identical `m` and `k`.
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{m: m, k: k, ref: into} = target, %__MODULE__{m: m, k: k, ref: from}) do
    Enum.each(1..m, fn idx ->
      if :atomics.get(from, idx) == 1 do
        :atomics.put(into, idx, 1)
      end
    end)

    target
  end

  def merge(%__MODULE__{} = f1, %__MODULE__{} = f2) do
    raise ArgumentError,
          "cannot merge filters with different parameters: " <>
            "filter1 has m=#{f1.m}, k=#{f1.k}; filter2 has m=#{f2.m}, k=#{f2.k}"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp hash(item, seed, m), do: :erlang.phash2({seed, item}, m)
end
```

## Failing test report

```
1 of 9 test(s) failed:

  * test false positive rate stays near the configured value
      
      
      False positive rate 0.277 exceeded 2x target 0.03
```
