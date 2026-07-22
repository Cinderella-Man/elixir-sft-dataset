# Fill in the middle: `ScalableBloomFilter.add/2`

Implement the public `add/2` function, which inserts `item` into a scalable
Bloom filter and returns the updated filter struct.

Its behavior:

- If `item` is already a tracked member (check `filter.items` with
  `MapSet.member?/2`), the item is a duplicate — return `filter` unchanged so
  duplicate inserts never inflate the count or capacity.
- Otherwise, split the slice list into the active (head) slice and the rest.
  Set the item's bits in the active slice using `set_bits/2` and increment that
  slice's `count`.
- If the active slice has now reached its capacity (`count >= capacity`), append
  a fresh, larger slice for future inserts: its index is the current number of
  slices (`length(filter.slices)`), built via `make_slice(index, filter.capacity0, filter.p0)`,
  and it becomes the new active (head) slice ahead of the updated old active
  slice and the rest. Otherwise keep the updated active slice as the head.
- Return the filter with the new `slices`, `count` incremented by 1, and `item`
  added to `items` via `MapSet.put/2`.

Items may be any Elixir term.

```elixir
defmodule ScalableBloomFilter do
  @moduledoc """
  A **scalable** Bloom filter that grows automatically to keep the compound
  false-positive probability bounded even as the number of inserted items far
  exceeds the initial capacity guess.

  The structure is a list of ordinary Bloom-filter *slices*. Inserts go into
  the newest (active) slice; when it fills, a larger slice with a tighter
  per-slice error rate is appended. Membership is the OR of membership across
  every slice.

  Growth constants: capacity factor `s = 2`, tightening ratio `r = 0.5`. For a
  target rate `P`, the first slice uses `p0 = P * (1 - r)` and slice `i` uses
  rate `p0 * r^i` with capacity `initial_capacity * s^i`. This bounds the total
  false-positive probability by `p0 / (1 - r) = P`.

  Because a Bloom filter can report false positives, relying on `member?/2`
  alone to reject duplicates would occasionally drop genuinely new items (a
  false positive on an unseen item), corrupting the `count`. To keep the
  distinct-item count and duplicate-suppression exact, the filter also tracks
  the set of inserted terms; `member?/2` itself remains a true probabilistic
  Bloom-filter query over the slices.
  """

  @ln2 :math.log(2)
  @growth 2
  @ratio 0.5

  @enforce_keys [:capacity0, :p0, :slices, :count, :items]
  defstruct [:capacity0, :p0, :slices, :count, :items]

  @type slice :: %{
          m: pos_integer(),
          k: pos_integer(),
          bits: tuple(),
          capacity: pos_integer(),
          count: non_neg_integer()
        }

  @type t :: %__MODULE__{
          capacity0: pos_integer(),
          p0: float(),
          slices: [slice()],
          count: non_neg_integer(),
          items: MapSet.t()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Creates a scalable filter with a single empty slice."
  @spec new(pos_integer(), float()) :: t()
  def new(initial_capacity, false_positive_rate)
      when is_integer(initial_capacity) and initial_capacity > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    p0 = false_positive_rate * (1 - @ratio)
    first = make_slice(0, initial_capacity, p0)

    %__MODULE__{
      capacity0: initial_capacity,
      p0: p0,
      slices: [first],
      count: 0,
      items: MapSet.new()
    }
  end

  @doc """
  Adds `item`. Duplicates are ignored (no double-counting). When the active
  slice fills, a larger slice is appended for future inserts.
  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{} = filter, item) do
    # TODO
  end

  @doc "Returns `true` if `item` is present in any slice."
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{slices: slices}, item) do
    Enum.any?(slices, fn slice -> slice_member?(slice, item) end)
  end

  @doc "Total number of distinct items inserted."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{count: count}), do: count

  @doc "Current number of slices."
  @spec num_slices(t()) :: pos_integer()
  def num_slices(%__MODULE__{slices: slices}), do: length(slices)

  # ---------------------------------------------------------------------------
  # Slice construction and bit operations
  # ---------------------------------------------------------------------------

  defp make_slice(index, capacity0, p0) do
    p_i = p0 * :math.pow(@ratio, index)
    capacity = max(1, round(capacity0 * :math.pow(@growth, index)))
    m = max(1, ceil(-capacity * :math.log(p_i) / (@ln2 * @ln2)))
    k = max(1, round(m / capacity * @ln2))
    num_words = ceil(m / 64)

    %{m: m, k: k, bits: Tuple.duplicate(0, num_words), capacity: capacity, count: 0}
  end

  defp set_bits(%{m: m, k: k, bits: bits}, item) do
    Enum.reduce(0..(k - 1), bits, fn seed, acc ->
      set_bit(acc, hash(item, seed, m))
    end)
  end

  defp slice_member?(%{m: m, k: k, bits: bits}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      get_bit(bits, hash(item, seed, m)) == 1
    end)
  end

  defp hash(item, seed, m), do: :erlang.phash2({seed, item}, m)

  defp set_bit(bits, bit_index) do
    wi = div(bit_index, 64)
    bo = rem(bit_index, 64)
    put_elem(bits, wi, Bitwise.bor(elem(bits, wi), Bitwise.bsl(1, bo)))
  end

  defp get_bit(bits, bit_index) do
    wi = div(bit_index, 64)
    bo = rem(bit_index, 64)
    Bitwise.band(Bitwise.bsr(elem(bits, wi), bo), 1)
  end
end
```