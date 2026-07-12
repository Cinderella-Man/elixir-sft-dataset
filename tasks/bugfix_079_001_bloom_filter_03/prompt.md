# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `BloomFilter` that implements a space-efficient probabilistic data structure for set membership testing.

I need these functions in the public API:
- `BloomFilter.new(expected_size, false_positive_rate)` which creates a new filter. It must automatically calculate the optimal bit array size (`m`) and number of hash functions (`k`) from the two parameters. `expected_size` is the anticipated number of items to be inserted, and `false_positive_rate` is a float between 0.0 and 1.0 (e.g. `0.01` for 1%). Store these as a struct.
- `BloomFilter.add(filter, item)` which hashes the item using `k` different hash functions and sets the corresponding bits. It must return an updated filter struct. Items can be any Elixir term.
- `BloomFilter.member?(filter, item)` which returns `true` if all `k` bits for this item are set, and `false` if any bit is unset. It must never return `false` for an item that was previously added (no false negatives), but may return `true` for items that were never added (false positives).
- `BloomFilter.merge(filter1, filter2)` which combines two filters by OR-ing their bit arrays together. Both filters must have been created with the same parameters — raise `ArgumentError` if `m` or `k` differ.

For hashing, derive `k` independent hash functions from a single `:erlang.phash2/2` or similar by seeding it differently for each function index (e.g. hashing a `{index, item}` tuple). Do not use any external dependency — stdlib only.

Give me the complete module in a single file with no external dependencies.

## The buggy module

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

      m = -ceil(n * ln(p) / ln(2)^2)   — number of bits
      k = round(m / n * ln(2))         — number of hash functions
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
      get_bit(bits, bit_index) == 2
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

## Failing test report

```
6 of 11 test(s) failed:

  * test member?/2 always returns true for added items (no false negatives)
      
      
      Expected "item-1" to be a member but got false
      

  * test atoms, integers, and tuples are never false-negatives
      
      
      Expected truthy, got false
      code: assert BloomFilter.member?(filter, item)
      arguments:
      
               # 1
               %BloomFilter{m: 480, k: 7, bits: {4670796934452084744, 9223935124247216128, 13521793998389248, 18023194602504256, 108988989440, 70369214203936, 576742227414351872, 388}}
      
               # 2
               :alpha
      
      

  * test merge/2 contains all items from both filters
      
      
      Expected truthy, got false
      code: assert BloomFilter.member?(merged, "a-#{i}")
      arguments:
      
               # 1
               %BloomFilter{m: 1918, k: 7, bits: {3567262077732321182, 15087206728851363179, 18417382730607025708, 5949236808860680517, 5636820866425971585, 5073075874840369766, 4734511261416743866, 85537759816208573, 17455508721173036035, 13113377097487722885, 17541848752824813543, 2216960435845748727, 7788587279093545214, 17769151636316027308, 6705988693012504753, 11101709640171087070, 1612314222

  * test merge/2 with an empty filter leaves the other unchanged
      
      
      Expected truthy, got false
      code: assert BloomFilter.member?(merged, "x")
      arguments:
      
               # 1
               %BloomFilter{m: 959, k: 7, bits: {16777216, 4294967296, 8589934592, 72057594037927936, 1090519040, 1125899907891200, 4503599627370496, 68719476736, 17592186046464, 1099514773504, 1153484454560268288, 2199023255584, 9007199254749184, 0, 0}}
      
               # 2
               "x"
      
      

  (…2 more)
```
