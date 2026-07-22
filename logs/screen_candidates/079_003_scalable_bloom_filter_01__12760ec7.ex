defmodule ScalableBloomFilter do
  @moduledoc """
  A scalable Bloom filter: a probabilistic set that grows on demand while keeping the
  compound false-positive probability bounded by the caller's target rate.

  The filter is a list of ordinary Bloom-filter *slices*. All adds go into the newest
  (active) slice. When the active slice reaches its capacity, a new, larger slice is
  appended with a tighter per-slice false-positive rate. Because the per-slice rates form
  a geometric series with ratio `r = 0.5` starting at `p0 = P * (1 - r)`, the sum of all
  per-slice rates stays below the target rate `P` no matter how many slices are created.

  ## Growth rules

  With capacity growth factor `s = 2` and error tightening ratio `r = 0.5`, slice `i`
  (0-indexed) has:

    * per-slice false-positive rate `p_i = p0 * r^i`
    * capacity `capacity_i = initial_capacity * s^i`
    * bit-array size `m_i = -ceil(capacity_i * ln(p_i) / (ln 2)^2)`
    * hash count `k_i = round(m_i / capacity_i * ln 2)`

  Membership is checked against every slice, so there are no false negatives. Adding an
  item that is already considered a member is a no-op, which prevents duplicate inserts
  from inflating the filter's capacity.

  ## Example

      iex> f = ScalableBloomFilter.new(100, 0.01)
      iex> f = ScalableBloomFilter.add(f, {:user, 42})
      iex> ScalableBloomFilter.member?(f, {:user, 42})
      true
      iex> ScalableBloomFilter.member?(f, {:user, 43})
      false
      iex> ScalableBloomFilter.count(f)
      1

  Bits are stored in a `MapSet` of integer positions, so memory use is proportional to the
  number of set bits rather than to the nominal bit-array size.
  """

  @typedoc "A single Bloom-filter slice."
  @opaque slice :: %{
            index: non_neg_integer(),
            bits: MapSet.t(non_neg_integer()),
            num_bits: pos_integer(),
            num_hashes: pos_integer(),
            capacity: pos_integer(),
            count: non_neg_integer()
          }

  @typedoc "A scalable Bloom filter."
  @type t :: %__MODULE__{
          initial_capacity: pos_integer(),
          false_positive_rate: float(),
          count: non_neg_integer(),
          slices: [slice(), ...]
        }

  @enforce_keys [:initial_capacity, :false_positive_rate, :count, :slices]
  defstruct [:initial_capacity, :false_positive_rate, :count, :slices]

  # Capacity growth factor.
  @growth 2
  # Error tightening ratio.
  @tightening 0.5

  @ln2 0.6931471805599453
  @ln2_squared 0.4804530139182014

  @doc """
  Creates a scalable Bloom filter with a single empty slice (index 0).

  `initial_capacity` must be a positive integer and is the capacity of the first slice.
  `false_positive_rate` must be a float strictly between `0.0` and `1.0`; it bounds the
  compound false-positive probability of the whole filter.

  ## Examples

      iex> f = ScalableBloomFilter.new(1_000, 0.001)
      iex> ScalableBloomFilter.num_slices(f)
      1
      iex> ScalableBloomFilter.count(f)
      0
  """
  @spec new(pos_integer(), float()) :: t()
  def new(initial_capacity, false_positive_rate)
      when is_integer(initial_capacity) and initial_capacity > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    %__MODULE__{
      initial_capacity: initial_capacity,
      false_positive_rate: false_positive_rate,
      count: 0,
      slices: [build_slice(0, initial_capacity, false_positive_rate)]
    }
  end

  @doc """
  Adds `item` to the filter and returns the updated filter.

  If `item` is already a member (possibly a false positive), the filter is returned
  unchanged. Otherwise the item's bits are set in the active (newest) slice and the total
  count is incremented; if the active slice then reaches its capacity, a fresh, larger
  slice is appended for future inserts.

  Items may be any Elixir term.

  ## Examples

      iex> f = ScalableBloomFilter.new(10, 0.01)
      iex> f = ScalableBloomFilter.add(f, "hello")
      iex> f = ScalableBloomFilter.add(f, "hello")
      iex> ScalableBloomFilter.count(f)
      1
  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{} = filter, item) do
    if member?(filter, item) do
      filter
    else
      [active | older] = filter.slices
      updated = set_bits(active, item)
      slices = maybe_grow(updated, older, filter)
      %__MODULE__{filter | count: filter.count + 1, slices: slices}
    end
  end

  @doc """
  Returns `true` if `item` is present in any slice, `false` otherwise.

  A `true` result may be a false positive (bounded by the configured rate); a `false`
  result is always correct — there are no false negatives.

  ## Examples

      iex> f = ScalableBloomFilter.new(100, 0.01) |> ScalableBloomFilter.add(:a)
      iex> ScalableBloomFilter.member?(f, :a)
      true
      iex> ScalableBloomFilter.member?(f, :b)
      false
  """
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{slices: slices}, item) do
    Enum.any?(slices, &slice_member?(&1, item))
  end

  @doc """
  Returns the total number of distinct items inserted into the filter.

  Items rejected by `add/2` as already-present (including false positives) are not
  counted.

  ## Examples

      iex> f = ScalableBloomFilter.new(100, 0.01)
      iex> ScalableBloomFilter.count(ScalableBloomFilter.add(f, :a))
      1
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{count: count}), do: count

  @doc """
  Returns the current number of slices, which grows as the filter fills up.

  ## Examples

      iex> f = ScalableBloomFilter.new(2, 0.01)
      iex> f = Enum.reduce([:a, :b], f, &ScalableBloomFilter.add(&2, &1))
      iex> ScalableBloomFilter.num_slices(f)
      2
  """
  @spec num_slices(t()) :: pos_integer()
  def num_slices(%__MODULE__{slices: slices}), do: length(slices)

  # -- internals -------------------------------------------------------------------

  # Appends a new, larger slice when the active one has just reached capacity. The active
  # slice stays at the head of the list until it is superseded, so `slices` is ordered
  # newest-first.
  @spec maybe_grow(slice(), [slice()], t()) :: [slice(), ...]
  defp maybe_grow(%{count: count, capacity: capacity, index: index} = active, older, filter)
       when count >= capacity do
    next =
      build_slice(
        index + 1,
        slice_capacity(filter.initial_capacity, index + 1),
        filter.false_positive_rate
      )

    [next, active | older]
  end

  defp maybe_grow(active, older, _filter), do: [active | older]

  @spec build_slice(non_neg_integer(), pos_integer(), float()) :: slice()
  defp build_slice(index, capacity, false_positive_rate) do
    p = slice_error_rate(false_positive_rate, index)
    num_bits = max(1, -ceil(capacity * :math.log(p) / @ln2_squared))
    num_hashes = max(1, round(num_bits / capacity * @ln2))

    %{
      index: index,
      bits: MapSet.new(),
      num_bits: num_bits,
      num_hashes: num_hashes,
      capacity: capacity,
      count: 0
    }
  end

  # capacity_i = initial_capacity * s^i
  @spec slice_capacity(pos_integer(), non_neg_integer()) :: pos_integer()
  defp slice_capacity(initial_capacity, index) do
    initial_capacity * Integer.pow(@growth, index)
  end

  # p_i = P * (1 - r) * r^i
  @spec slice_error_rate(float(), non_neg_integer()) :: float()
  defp slice_error_rate(false_positive_rate, index) do
    p0 = false_positive_rate * (1 - @tightening)
    p0 * :math.pow(@tightening, index)
  end

  @spec set_bits(slice(), term()) :: slice()
  defp set_bits(slice, item) do
    bits = Enum.reduce(positions(slice, item), slice.bits, &MapSet.put(&2, &1))
    %{slice | bits: bits, count: slice.count + 1}
  end

  @spec slice_member?(slice(), term()) :: boolean()
  defp slice_member?(slice, item) do
    Enum.all?(positions(slice, item), &MapSet.member?(slice.bits, &1))
  end

  # k independent hashes derived from :erlang.phash2/2 over {hash_index, item}.
  @spec positions(slice(), term()) :: [non_neg_integer()]
  defp positions(%{num_hashes: num_hashes, num_bits: num_bits}, item) do
    Enum.map(0..(num_hashes - 1), fn i ->
      :erlang.phash2({i, item}, num_bits)
    end)
  end
end