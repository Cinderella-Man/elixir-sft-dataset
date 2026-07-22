defmodule BloomFilter do
  @moduledoc """
  A space-efficient probabilistic data structure for set membership testing.

  A Bloom filter stores a bit array of size `m` and uses `k` hash functions.
  Adding an item sets `k` bits; membership testing checks those same `k` bits.
  False positives are possible (`member?/2` may return `true` for an item that
  was never added), but false negatives are not: an item that was added always
  reports as a member.

  The bit array is represented as a tuple of integers, each used as a 64-bit
  word. Bit index `i` lives at offset `rem(i, 64)` of word `div(i, 64)`, so the
  tuple has `ceil(m / 64)` elements. A fresh filter has every word set to `0`.

  All operations are purely functional: no function mutates its input struct.

  The `k` hash functions are derived from `:erlang.phash2/2` by seeding it with
  the function index: the bit index for seed `i` is `:erlang.phash2({i, item}, m)`.
  Hashing is therefore deterministic across calls, processes and filters that
  share the same `m`.

  ## Example

      iex> filter = BloomFilter.new(1_000, 0.01)
      iex> filter = BloomFilter.add(filter, "hello")
      iex> BloomFilter.member?(filter, "hello")
      true

  """

  @word_bits 64

  @enforce_keys [:m, :k, :bits]
  defstruct [:m, :k, :bits]

  @type t :: %__MODULE__{
          m: pos_integer(),
          k: pos_integer(),
          bits: tuple()
        }

  @doc """
  Creates a new, empty filter sized for `expected_size` items and a target
  `false_positive_rate`.

  The optimal parameters are derived as:

    * `m = ceil(-n * ln(p) / ln(2)^2)`
    * `k = max(1, round(m / n * ln(2)))`

  `expected_size` must be a positive integer and `false_positive_rate` a float
  strictly between `0.0` and `1.0`; any other input raises `FunctionClauseError`.

  ## Examples

      iex> filter = BloomFilter.new(1_000, 0.01)
      iex> {filter.m, filter.k, tuple_size(filter.bits)}
      {9586, 7, 150}

      iex> filter = BloomFilter.new(1_000, 0.9)
      iex> {filter.m, filter.k}
      {220, 1}

  """
  @spec new(pos_integer(), float()) :: t()
  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    n = expected_size
    p = false_positive_rate

    m = ceil(-n * :math.log(p) / (:math.log(2) * :math.log(2)))
    k = max(1, round(m / n * :math.log(2)))

    words = div(m + @word_bits - 1, @word_bits)
    bits = Tuple.duplicate(0, words)

    %__MODULE__{m: m, k: k, bits: bits}
  end

  @doc """
  Adds `item` (any Elixir term) to the filter, returning an updated filter.

  Only `:bits` may change; `:m` and `:k` are preserved. Bits are only ever set,
  never cleared, so the operation is idempotent and order-independent.

  ## Examples

      iex> filter = BloomFilter.new(100, 0.01) |> BloomFilter.add(:a)
      iex> BloomFilter.add(filter, :a) == filter
      true

  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{m: m, k: k, bits: bits} = filter, item) do
    new_bits =
      Enum.reduce(0..(k - 1), bits, fn i, acc ->
        set_bit(acc, :erlang.phash2({i, item}, m))
      end)

    %__MODULE__{filter | bits: new_bits}
  end

  @doc """
  Returns `true` if all `k` bits for `item` are set, `false` otherwise.

  There are no false negatives: an item that was added (directly or via a
  `merge/2` input) always returns `true`. False positives are possible.

  ## Examples

      iex> filter = BloomFilter.new(100, 0.01)
      iex> BloomFilter.member?(filter, "nope")
      false

  """
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{m: m, k: k, bits: bits}, item) do
    Enum.all?(0..(k - 1), fn i ->
      bit_set?(bits, :erlang.phash2({i, item}, m))
    end)
  end

  @doc """
  Merges two filters by OR-ing their bit arrays word by word.

  The result contains the union of both item sets: `member?/2` returns `true` on
  the merged filter for every item added to either input. Merging is commutative,
  associative and idempotent.

  Both filters must share the same `m` and `k`; otherwise an `ArgumentError` is
  raised. Non-struct arguments raise `FunctionClauseError`.

  ## Examples

      iex> a = BloomFilter.new(100, 0.01) |> BloomFilter.add(:a)
      iex> b = BloomFilter.new(100, 0.01) |> BloomFilter.add(:b)
      iex> merged = BloomFilter.merge(a, b)
      iex> {BloomFilter.member?(merged, :a), BloomFilter.member?(merged, :b)}
      {true, true}

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{m: m, k: k, bits: bits1}, %__MODULE__{m: m, k: k, bits: bits2}) do
    merged =
      bits1
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(bits2))
      |> Enum.map(fn {w1, w2} -> Bitwise.bor(w1, w2) end)
      |> List.to_tuple()

    %__MODULE__{m: m, k: k, bits: merged}
  end

  def merge(%__MODULE__{} = filter1, %__MODULE__{} = filter2) do
    raise ArgumentError,
          "cannot merge filters with different parameters: " <>
            "filter1 has m=#{filter1.m}, k=#{filter1.k}; " <>
            "filter2 has m=#{filter2.m}, k=#{filter2.k}"
  end

  @spec set_bit(tuple(), non_neg_integer()) :: tuple()
  defp set_bit(bits, index) do
    word_index = div(index, @word_bits)
    offset = rem(index, @word_bits)
    word = elem(bits, word_index)
    put_elem(bits, word_index, Bitwise.bor(word, Bitwise.bsl(1, offset)))
  end

  @spec bit_set?(tuple(), non_neg_integer()) :: boolean()
  defp bit_set?(bits, index) do
    word_index = div(index, @word_bits)
    offset = rem(index, @word_bits)
    word = elem(bits, word_index)
    Bitwise.band(Bitwise.bsr(word, offset), 1) == 1
  end
end