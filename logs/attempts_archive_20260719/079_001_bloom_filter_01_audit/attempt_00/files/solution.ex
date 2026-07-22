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
