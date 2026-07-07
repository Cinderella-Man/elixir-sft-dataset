# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  @ln2 :math.log(2)

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

## Test harness — implement the `# TODO` test

```elixir
defmodule ConcurrentBloomFilterTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/2 computes m and k and allocates an atomics-backed filter" do
    # TODO
  end

  # -------------------------------------------------------
  # Shared mutable semantics
  # -------------------------------------------------------

  test "adds are visible across processes sharing the handle" do
    filter = ConcurrentBloomFilter.new(100, 0.01)

    task =
      Task.async(fn ->
        ConcurrentBloomFilter.add(filter, "written-elsewhere")
      end)

    Task.await(task)

    # The mutation happened in another process but is visible here because the
    # backing :atomics array is shared.
    assert ConcurrentBloomFilter.member?(filter, "written-elsewhere")
  end

  # -------------------------------------------------------
  # No false negatives
  # -------------------------------------------------------

  test "member?/2 true for all added items (single process)" do
    filter = ConcurrentBloomFilter.new(500, 0.01)
    items = for i <- 1..500, do: "item-#{i}"
    Enum.each(items, fn item -> ConcurrentBloomFilter.add(filter, item) end)

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item)
    end
  end

  test "mixed term types are never false-negatives" do
    filter = ConcurrentBloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    Enum.each(items, fn item -> ConcurrentBloomFilter.add(filter, item) end)

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item)
    end
  end

  # -------------------------------------------------------
  # Concurrent writes
  # -------------------------------------------------------

  test "concurrent adds from many processes lose no items" do
    filter = ConcurrentBloomFilter.new(5_000, 0.01)
    items = for i <- 1..5_000, do: "concurrent-#{i}"

    items
    |> Task.async_stream(
      fn item -> ConcurrentBloomFilter.add(filter, item) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Stream.run()

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to survive concurrent insertion"
    end
  end

  # -------------------------------------------------------
  # False positive rate
  # -------------------------------------------------------

  test "false positive rate stays near the configured value" do
    n = 1_000
    p = 0.03
    filter = ConcurrentBloomFilter.new(n, p)

    Enum.each(1..n, fn i -> ConcurrentBloomFilter.add(filter, "present-#{i}") end)

    false_positives =
      Enum.count(1..n, fn i -> ConcurrentBloomFilter.member?(filter, "absent-#{i}") end)

    observed = false_positives / n
    assert observed < p * 2,
           "False positive rate #{observed} exceeded 2x target #{p}"
  end

  # -------------------------------------------------------
  # Empty filter
  # -------------------------------------------------------

  test "empty filter reports no members" do
    filter = ConcurrentBloomFilter.new(100, 0.01)
    refute ConcurrentBloomFilter.member?(filter, "ghost")
    refute ConcurrentBloomFilter.member?(filter, 0)
    refute ConcurrentBloomFilter.member?(filter, :nope)
  end

  # -------------------------------------------------------
  # Merge
  # -------------------------------------------------------

  test "merge/2 ORs the source into the target in place" do
    into = ConcurrentBloomFilter.new(200, 0.01)
    from = ConcurrentBloomFilter.new(200, 0.01)

    Enum.each(1..100, fn i -> ConcurrentBloomFilter.add(into, "a-#{i}") end)
    Enum.each(1..100, fn i -> ConcurrentBloomFilter.add(from, "b-#{i}") end)

    result = ConcurrentBloomFilter.merge(into, from)

    for i <- 1..100 do
      assert ConcurrentBloomFilter.member?(result, "a-#{i}")
      assert ConcurrentBloomFilter.member?(result, "b-#{i}")
    end

    # `into` was mutated in place and now also contains from's items.
    assert ConcurrentBloomFilter.member?(into, "b-1")
  end

  test "merge/2 raises when parameters differ" do
    f1 = ConcurrentBloomFilter.new(100, 0.01)
    f2 = ConcurrentBloomFilter.new(999, 0.05)

    assert_raise ArgumentError, fn -> ConcurrentBloomFilter.merge(f1, f2) end
  end
end
```
