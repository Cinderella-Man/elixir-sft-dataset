# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule BloomFilter do
  @moduledoc """
  A space-efficient probabilistic data structure for set membership testing.

  A Bloom filter can tell you with certainty that an item has **not** been added,
  but can only say with some probability that an item **has** been added (false
  positives are possible; false negatives are not).

  ## Example

      iex> filter = BloomFilter.new(1_000, 0.01)
      iex> filter = BloomFilter.add(filter, "hello")
      iex> filter = BloomFilter.add(filter, :world)
      iex> BloomFilter.member?(filter, "hello")
      true
      iex> BloomFilter.member?(filter, "never_added")
      false  # (with very high probability)

  ## Parameter selection

  Given an expected number of items `n` and a desired false-positive rate `p`,
  the optimal parameters are derived as:

      m = ceil(-n * ln(p) / ln(2)^2)     — number of bits
      k = max(1, round(m / n * ln(2)))   — number of hash functions
  """

  @enforce_keys [:m, :k, :bits]
  defstruct [:m, :k, :bits]

  @type t :: %__MODULE__{
          m: pos_integer(),
          k: pos_integer(),
          bits: tuple()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new, empty Bloom filter.

  ## Parameters

    - `expected_size`      – anticipated number of items to be inserted (`n`).
    - `false_positive_rate` – desired false-positive probability, e.g. `0.01`
                              for 1%.  Must be in the range `(0.0, 1.0)`.

  ## Examples

      iex> BloomFilter.new(1_000, 0.01)
      %BloomFilter{m: 9586, k: 7, bits: ...}

  """
  @spec new(pos_integer(), float()) :: t()
  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = optimal_m(expected_size, false_positive_rate)
    k = optimal_k(m, expected_size)

    # Represent bits as a tuple of integers where each integer is used as a
    # 64-bit word.  This gives O(1) element access via `elem/2`.
    num_words = ceil(m / 64)
    bits = Tuple.duplicate(0, num_words)

    %__MODULE__{m: m, k: k, bits: bits}
  end

  @doc """
  Adds `item` to the filter and returns the updated filter.

  The item may be any Elixir term.  The filter is purely functional — the
  original struct is not mutated.
  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{m: m, k: k, bits: bits} = filter, item) do
    new_bits =
      Enum.reduce(0..(k - 1), bits, fn seed, acc ->
        bit_index = hash(item, seed, m)
        set_bit(acc, bit_index)
      end)

    %{filter | bits: new_bits}
  end

  @doc """
  Returns `true` if `item` is (probably) a member of the filter.

  Returns `false` only if the item was *definitely* never added.  A `true`
  result may occasionally occur for items that were never added (false
  positive), but a `false` result is always accurate (no false negatives).
  """
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{m: m, k: k, bits: bits}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      bit_index = hash(item, seed, m)
      get_bit(bits, bit_index) == 1
    end)
  end

  @doc """
  Merges two Bloom filters by OR-ing their bit arrays.

  The resulting filter represents the union of both filters' item sets.  Both
  filters **must** have been created with the same `m` and `k` parameters;
  an `ArgumentError` is raised otherwise.

  ## Examples

      iex> f1 = BloomFilter.new(500, 0.01) |> BloomFilter.add("alice")
      iex> f2 = BloomFilter.new(500, 0.01) |> BloomFilter.add("bob")
      iex> merged = BloomFilter.merge(f1, f2)
      iex> BloomFilter.member?(merged, "alice")
      true
      iex> BloomFilter.member?(merged, "bob")
      true

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{m: m, k: k} = f1, %__MODULE__{m: m, k: k} = f2) do
    merged_bits =
      f1.bits
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(f2.bits))
      |> Enum.map(fn {w1, w2} -> Bitwise.bor(w1, w2) end)
      |> List.to_tuple()

    %{f1 | bits: merged_bits}
  end

  def merge(%__MODULE__{} = f1, %__MODULE__{} = f2) do
    raise ArgumentError,
          "cannot merge filters with different parameters: " <>
            "filter1 has m=#{f1.m}, k=#{f1.k}; " <>
            "filter2 has m=#{f2.m}, k=#{f2.k}"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Optimal bit-array size:
  #   m = -ceil( n * ln(p) / (ln 2)^2 )
  @ln2 :math.log(2)

  defp optimal_m(n, p) do
    ceil(-n * :math.log(p) / (@ln2 * @ln2))
  end

  # Optimal number of hash functions:
  #   k = round( (m / n) * ln 2 )
  defp optimal_k(m, n) do
    max(1, round(m / n * @ln2))
  end

  # Derive k independent hash values from a single hash primitive by hashing
  # the tuple {seed, item}.  :erlang.phash2/2 accepts any Erlang term and
  # returns a non-negative integer in 0..range-1.
  defp hash(item, seed, m) do
    :erlang.phash2({seed, item}, m)
  end

  # Each "word" in the `bits` tuple holds 64 bits.
  defp word_index(bit_index), do: div(bit_index, 64)
  defp bit_offset(bit_index), do: rem(bit_index, 64)

  defp set_bit(bits, bit_index) do
    wi = word_index(bit_index)
    bo = bit_offset(bit_index)
    word = elem(bits, wi)
    put_elem(bits, wi, Bitwise.bor(word, Bitwise.bsl(1, bo)))
  end

  defp get_bit(bits, bit_index) do
    wi = word_index(bit_index)
    bo = bit_offset(bit_index)
    word = elem(bits, wi)
    Bitwise.band(Bitwise.bsr(word, bo), 1)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule BloomFilterTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/2 produces a struct with computed m and k" do
    filter = BloomFilter.new(1_000, 0.01)

    # Optimal m for n=1000, p=0.01 is ~9585 bits; k is ~7
    assert filter.m > 0
    assert filter.k > 0

    # Sanity: tighter false-positive rate → larger bit array
    loose = BloomFilter.new(1_000, 0.10)
    tight = BloomFilter.new(1_000, 0.01)
    assert tight.m > loose.m
  end

  test "new/2 with different expected sizes scales m accordingly" do
    small = BloomFilter.new(100, 0.01)
    large = BloomFilter.new(10_000, 0.01)
    assert large.m > small.m
  end

  # -------------------------------------------------------
  # No false negatives
  # -------------------------------------------------------

  test "member?/2 always returns true for added items (no false negatives)" do
    filter = BloomFilter.new(500, 0.01)

    items = for i <- 1..500, do: "item-#{i}"
    filter = Enum.reduce(items, filter, &BloomFilter.add(&2, &1))

    for item <- items do
      assert BloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member but got false"
    end
  end

  test "atoms, integers, and tuples are never false-negatives" do
    filter = BloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    filter = Enum.reduce(items, filter, &BloomFilter.add(&2, &1))

    for item <- items do
      assert BloomFilter.member?(filter, item)
    end
  end

  # -------------------------------------------------------
  # False positive rate
  # -------------------------------------------------------

  test "false positive rate stays near the configured value" do
    n = 1_000
    p = 0.03
    filter = BloomFilter.new(n, p)

    # Add n distinct items
    filter =
      Enum.reduce(1..n, filter, fn i, f ->
        BloomFilter.add(f, "present-#{i}")
      end)

    # Test n absent items and count false positives
    false_positives =
      Enum.count(1..n, fn i ->
        BloomFilter.member?(filter, "absent-#{i}")
      end)

    observed_rate = false_positives / n

    # Allow 2× headroom around the configured rate
    assert observed_rate < p * 2,
           "False positive rate #{observed_rate} exceeded 2× target #{p}"
  end

  # -------------------------------------------------------
  # Empty filter
  # -------------------------------------------------------

  test "empty filter reports no members" do
    filter = BloomFilter.new(100, 0.01)

    refute BloomFilter.member?(filter, "ghost")
    refute BloomFilter.member?(filter, 0)
    refute BloomFilter.member?(filter, :nope)
  end

  # -------------------------------------------------------
  # Merge
  # -------------------------------------------------------

  test "merge/2 contains all items from both filters" do
    f1 = BloomFilter.new(200, 0.01)
    f2 = BloomFilter.new(200, 0.01)

    f1 = Enum.reduce(1..100, f1, fn i, f -> BloomFilter.add(f, "a-#{i}") end)
    f2 = Enum.reduce(1..100, f2, fn i, f -> BloomFilter.add(f, "b-#{i}") end)

    merged = BloomFilter.merge(f1, f2)

    for i <- 1..100 do
      assert BloomFilter.member?(merged, "a-#{i}")
      assert BloomFilter.member?(merged, "b-#{i}")
    end
  end

  test "merge/2 raises ArgumentError when filters have different parameters" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(999, 0.05)

    assert_raise ArgumentError, fn ->
      BloomFilter.merge(f1, f2)
    end
  end

  test "merge/2 with an empty filter leaves the other unchanged" do
    f1 = BloomFilter.new(100, 0.01)
    empty = BloomFilter.new(100, 0.01)

    f1 = Enum.reduce(["x", "y", "z"], f1, &BloomFilter.add(&2, &1))
    merged = BloomFilter.merge(f1, empty)

    assert BloomFilter.member?(merged, "x")
    assert BloomFilter.member?(merged, "y")
    assert BloomFilter.member?(merged, "z")
  end

  test "merge/2 is commutative" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(100, 0.01)

    f1 = BloomFilter.add(f1, "only-in-f1")
    f2 = BloomFilter.add(f2, "only-in-f2")

    m1 = BloomFilter.merge(f1, f2)
    m2 = BloomFilter.merge(f2, f1)

    assert BloomFilter.member?(m1, "only-in-f1")
    assert BloomFilter.member?(m1, "only-in-f2")
    assert BloomFilter.member?(m2, "only-in-f1")
    assert BloomFilter.member?(m2, "only-in-f2")

    # Bit arrays should be identical
    assert m1.bits == m2.bits
  end

  # -------------------------------------------------------
  # Idempotency
  # -------------------------------------------------------

  test "adding the same item multiple times has no extra effect" do
    f = BloomFilter.new(10, 0.01)
    f1 = BloomFilter.add(f, "dup")
    f2 = BloomFilter.add(f1, "dup")

    assert f1.bits == f2.bits
    assert BloomFilter.member?(f2, "dup")
  end

  # -------------------------------------------------------
  # Guard boundaries on new/2 (documented: exclusive ranges)
  # -------------------------------------------------------

  test "new/2 rejects sizes <= 0 and rates outside (0.0, 1.0) with FunctionClauseError" do
    assert_raise FunctionClauseError, fn -> BloomFilter.new(0, 0.01) end
    assert_raise FunctionClauseError, fn -> BloomFilter.new(-5, 0.01) end
    assert_raise FunctionClauseError, fn -> BloomFilter.new(100, 0.0) end
    assert_raise FunctionClauseError, fn -> BloomFilter.new(100, 1.0) end
    assert_raise FunctionClauseError, fn -> BloomFilter.new(100, 1) end
  end

  test "new/2 accepts the smallest positive expected size (n = 1)" do
    filter = BloomFilter.new(1, 0.5)

    assert %BloomFilter{} = filter
    assert filter.m >= 1
    assert filter.k >= 1
    assert BloomFilter.member?(BloomFilter.add(filter, :only), :only)
  end

  # -------------------------------------------------------
  # Documented parameter derivation and bit-array shape
  # -------------------------------------------------------

  test "new/2 derives the documented m, k, word count and all-zero words" do
    filter = BloomFilter.new(1_000, 0.01)

    assert filter.m == 9586
    assert filter.k == 7
    # ceil(m / 64) 64-bit words
    assert tuple_size(filter.bits) == 150
    assert Enum.all?(Tuple.to_list(filter.bits), &(&1 == 0))
  end

  test "new/2 floors k at 1 for a very loose false-positive rate" do
    # TODO
  end

  # -------------------------------------------------------
  # Exact hashing / bit layout
  # -------------------------------------------------------

  test "add/2 sets exactly the bits phash2({i, item}, m) for i in 0..k-1" do
    filter = BloomFilter.new(1_000, 0.01)

    for item <- ["probe-a", :probe_b, 12_345, {:probe, "c"}, [1, 2, 3]] do
      added = BloomFilter.add(filter, item)
      expected = MapSet.new(hash_indices(filter, item))

      assert set_bit_indices(added.bits) == expected
      assert tuple_size(added.bits) == tuple_size(filter.bits)
      assert added.m == filter.m
      assert added.k == filter.k
    end
  end

  test "member?/2 needs every one of the k bits, first and last seed included" do
    filter = BloomFilter.new(1_000, 0.01)

    # Pick a probe whose k bit indices are all distinct, so that dropping any
    # single one of them really leaves that bit unset.
    item =
      Enum.find(Enum.map(0..99, &"seed-probe-#{&1}"), fn candidate ->
        indices = hash_indices(filter, candidate)
        length(Enum.uniq(indices)) == filter.k
      end)

    assert item
    indices = hash_indices(filter, item)

    full = %BloomFilter{filter | bits: bits_from_indices(indices, filter.m)}
    assert BloomFilter.member?(full, item)

    for dropped <- [List.first(indices), List.last(indices)] do
      remaining = indices -- [dropped]
      partial = %BloomFilter{filter | bits: bits_from_indices(remaining, filter.m)}

      refute BloomFilter.member?(partial, item)
    end
  end

  # -------------------------------------------------------
  # Helpers (mirror the documented hashing and bit layout)
  # -------------------------------------------------------

  defp hash_indices(%BloomFilter{k: k, m: m}, item) do
    for i <- 0..(k - 1), do: :erlang.phash2({i, item}, m)
  end

  defp bits_from_indices(indices, m) do
    empty = Tuple.duplicate(0, ceil(m / 64))

    Enum.reduce(indices, empty, fn index, acc ->
      wi = div(index, 64)
      word = Bitwise.bor(elem(acc, wi), Bitwise.bsl(1, rem(index, 64)))
      put_elem(acc, wi, word)
    end)
  end

  defp set_bit_indices(bits) do
    bits
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.flat_map(fn {word, wi} ->
      for bo <- 0..63, Bitwise.band(Bitwise.bsr(word, bo), 1) == 1, do: wi * 64 + bo
    end)
    |> MapSet.new()
  end

  test "merge/2 raises FunctionClauseError when an argument is not a filter struct" do
    f = BloomFilter.new(100, 0.01)
    look_alike = %{m: f.m, k: f.k, bits: f.bits}

    assert_raise FunctionClauseError, fn -> BloomFilter.merge(f, look_alike) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(look_alike, f) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(nil, f) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(f, :not_a_filter) end
  end

  test "merge/2 error message names both filters' m and k values" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(999, 0.05)

    error = assert_raise ArgumentError, fn -> BloomFilter.merge(f1, f2) end

    assert error.message =~ "cannot merge filters with different parameters"
    assert error.message =~ "filter1 has m=#{f1.m}, k=#{f1.k}"
    assert error.message =~ "filter2 has m=#{f2.m}, k=#{f2.k}"
  end

  test "merge/2 is associative and idempotent on identical inputs" do
    a = BloomFilter.new(100, 0.01) |> BloomFilter.add("a-item")
    b = BloomFilter.new(100, 0.01) |> BloomFilter.add("b-item")
    c = BloomFilter.new(100, 0.01) |> BloomFilter.add({:c, 3})

    left = BloomFilter.merge(BloomFilter.merge(a, b), c)
    right = BloomFilter.merge(a, BloomFilter.merge(b, c))

    assert left == right
    assert BloomFilter.merge(a, a) == a
    assert BloomFilter.merge(left, left) == left
    assert BloomFilter.member?(left, "a-item")
    assert BloomFilter.member?(left, "b-item")
    assert BloomFilter.member?(left, {:c, 3})
  end

  test "add/2 yields equal structs regardless of insertion order" do
    empty = BloomFilter.new(100, 0.01)
    items = ["x", :y, 3, {4, "z"}, [5, 6]]

    build = fn list -> Enum.reduce(list, empty, &BloomFilter.add(&2, &1)) end

    forward = build.(items)
    backward = build.(Enum.reverse(items))
    rotated = build.(tl(items) ++ [hd(items)])

    assert forward == backward
    assert forward == rotated
    assert forward.bits == rotated.bits
  end

  test "add/2 preserves every previously set bit as items accumulate" do
    start = BloomFilter.new(200, 0.01)

    Enum.reduce(1..50, start, fn i, f ->
      next = BloomFilter.add(f, {:grow, i})

      assert tuple_size(next.bits) == tuple_size(f.bits)

      for wi <- 0..(tuple_size(f.bits) - 1) do
        old_word = elem(f.bits, wi)
        assert Bitwise.band(old_word, elem(next.bits, wi)) == old_word
      end

      assert BloomFilter.member?(next, {:grow, i})
      next
    end)
  end

  test "new/2 returns equal structs for repeated calls with identical arguments" do
    assert BloomFilter.new(1_000, 0.01) == BloomFilter.new(1_000, 0.01)
    assert BloomFilter.new(7, 0.25) == BloomFilter.new(7, 0.25)
    assert BloomFilter.new(1_000, 0.9) == BloomFilter.new(1_000, 0.9)
  end
end
```
