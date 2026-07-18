# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `set_bits` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `ScalableBloomFilter` that implements a **scalable** Bloom filter — one that automatically grows to keep a bounded false-positive rate even when the number of inserted items greatly exceeds the initial guess.

A scalable Bloom filter is a list of ordinary Bloom-filter **slices**. Adds always go into the newest (active) slice. When the active slice reaches its capacity, a new, larger slice is appended with a *tighter* per-slice false-positive rate, so the compound false-positive probability stays bounded no matter how many items arrive.

Use these growth rules (fixed constants): capacity growth factor `s = 2` and error tightening ratio `r = 0.5`. Given the caller's target rate `P`, set the first slice's rate to `p0 = P * (1 - r)`. Slice `i` (0-indexed) then has:
- per-slice false-positive rate `p_i = p0 * r^i`
- capacity `capacity_i = initial_capacity * s^i`
- bit-array size `m_i = -ceil(capacity_i * ln(p_i) / (ln 2)^2)` and hash count `k_i = round(m_i / capacity_i * ln 2)`

I need these functions in the public API:

- `ScalableBloomFilter.new(initial_capacity, false_positive_rate)` — creates a filter with a single empty slice (index 0). `initial_capacity` is a positive integer; `false_positive_rate` is a float strictly between 0.0 and 1.0. Store enough state in a struct to build further slices on demand and to track a total `count` of inserted items.
- `ScalableBloomFilter.add(filter, item)` — if the item has already been added, return the filter unchanged (this prevents duplicate inserts from inflating capacity). Duplicate detection must be **exact**: a genuinely new item must never be mistaken for a duplicate, even when the probabilistic membership query would report a false positive on it. Otherwise set the item's bits in the active slice and increment the total count; when the active slice reaches its capacity (its own item count is at least its capacity), append a fresh larger slice for future inserts. Return the updated filter. Items may be any Elixir term.
- `ScalableBloomFilter.member?(filter, item)` — returns `true` if the item is present in **any** slice, `false` only if it is absent from all of them (no false negatives). This is a probabilistic Bloom-filter query, so it may occasionally return `true` for an item that was never added.
- `ScalableBloomFilter.count(filter)` — total number of distinct items inserted. This count is exact (unaffected by Bloom-filter false positives): it equals the number of genuinely distinct items passed to `add`.
- `ScalableBloomFilter.num_slices(filter)` — the current number of slices (grows as the filter fills).

Derive `k` independent hashes per slice from `:erlang.phash2/2` on a `{index, item}` tuple. Stdlib only — no external dependencies. Give me the complete module in a single file.

## The module with `set_bits` missing

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
    if MapSet.member?(filter.items, item) do
      filter
    else
      [active | rest] = filter.slices

      active = %{
        active
        | bits: set_bits(active, item),
          count: active.count + 1
      }

      slices =
        if active.count >= active.capacity do
          index = length(filter.slices)
          fresh = make_slice(index, filter.capacity0, filter.p0)
          [fresh, active | rest]
        else
          [active | rest]
        end

      %{
        filter
        | slices: slices,
          count: filter.count + 1,
          items: MapSet.put(filter.items, item)
      }
    end
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
    # TODO
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

Give me only the complete implementation of `set_bits` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
