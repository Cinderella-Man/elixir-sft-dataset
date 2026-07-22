defmodule ConcurrentBloomFilter do
  @moduledoc """
  A lock-free, concurrently-writable Bloom filter backed by Erlang's `:atomics`.

  Unlike a purely functional Bloom filter, this implementation holds a single shared,
  mutable `:atomics` array (one slot per bit position). The array reference is a handle
  to off-heap memory, so every process holding the same `%ConcurrentBloomFilter{}` struct
  observes the same underlying bits — no GenServer, locks, or message passing required.

  Concurrency safety comes from the write pattern rather than from coordination: a slot is
  only ever *set* to `1` and never cleared, and `:atomics.put/3` is itself atomic. Two
  writers racing on the same slot both write the same value, so no update can be lost or
  torn, and no compare-and-swap retry loop is needed.

  ## Sizing

  Given an expected number of items `n` and a target false-positive rate `p`:

      m = -ceil(n * ln(p) / (ln 2)^2)     # number of bit slots
      k = round(m / n * ln 2)             # number of hash functions

  The `k` independent hashes are derived from `:erlang.phash2/2` applied to `{index, item}`
  tuples, so any Elixir term may be stored.

  ## Example

      iex> filter = ConcurrentBloomFilter.new(1_000, 0.01)
      iex> ConcurrentBloomFilter.add(filter, :hello)
      iex> ConcurrentBloomFilter.member?(filter, :hello)
      true
      iex> ConcurrentBloomFilter.member?(filter, :goodbye)
      false

  Adding from many processes at once is safe and requires no synchronization:

      filter = ConcurrentBloomFilter.new(100_000, 0.001)

      1..10_000
      |> Task.async_stream(fn i -> ConcurrentBloomFilter.add(filter, i) end)
      |> Stream.run()

  ## Caveats

  Bloom filters admit false positives but never false negatives: `member?/2` always returns
  `true` for an item that was added, but may occasionally return `true` for one that was
  not. Items cannot be removed.
  """

  @enforce_keys [:m, :k, :atomics]
  defstruct [:m, :k, :atomics]

  @type t :: %__MODULE__{
          m: pos_integer(),
          k: pos_integer(),
          atomics: :atomics.atomics_ref()
        }

  @ln2 0.6931471805599453
  @ln2_squared 0.4804530139182014

  @doc """
  Creates a new Bloom filter sized for `expected_size` items at `false_positive_rate`.

  `expected_size` must be a positive integer and `false_positive_rate` a float strictly
  between `0.0` and `1.0`. The optimal bit-array size `m` and hash count `k` are computed
  from those parameters, and an `:atomics` array of `m` unsigned slots is allocated.

  The returned struct is a handle to shared mutable memory: copying it between processes
  (or sending it in a message) does not copy the underlying bits.

  ## Examples

      iex> filter = ConcurrentBloomFilter.new(1_000, 0.01)
      iex> filter.k
      7

  """
  @spec new(pos_integer(), float()) :: t()
  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = optimal_m(expected_size, false_positive_rate)
    k = optimal_k(m, expected_size)

    %__MODULE__{m: m, k: k, atomics: :atomics.new(m, signed: false)}
  end

  @doc """
  Adds `item` to `filter`, atomically setting each of its `k` bit slots to `1`.

  Because the backing store is shared and mutable, the update is immediately visible to
  every process holding the same filter handle. This function is safe to call concurrently
  from any number of processes: slots are only ever set, never cleared, and each write is
  atomic, so concurrent adds cannot lose updates or corrupt the array.

  `item` may be any Elixir term. Returns the (unchanged) filter handle, so calls may be
  piped.

  ## Examples

      iex> filter = ConcurrentBloomFilter.new(100, 0.01)
      iex> ConcurrentBloomFilter.add(filter, {:user, 42})
      iex> ConcurrentBloomFilter.member?(filter, {:user, 42})
      true

  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{k: k, m: m, atomics: atomics} = filter, item) do
    Enum.each(0..(k - 1), fn index ->
      :atomics.put(atomics, slot(index, item, m), 1)
    end)

    filter
  end

  @doc """
  Returns `true` if every one of `item`'s `k` slots reads as `1`, `false` otherwise.

  There are no false negatives: an item that was added always reports `true`. False
  positives are possible at approximately the rate given to `new/2`.

  Reads are unsynchronized and lock-free; a `true` result means each slot was set at the
  moment it was read.

  ## Examples

      iex> filter = ConcurrentBloomFilter.new(100, 0.01)
      iex> ConcurrentBloomFilter.member?(filter, "absent")
      false
      iex> ConcurrentBloomFilter.add(filter, "present")
      iex> ConcurrentBloomFilter.member?(filter, "present")
      true

  """
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{k: k, m: m, atomics: atomics}, item) do
    Enum.all?(0..(k - 1), fn index ->
      :atomics.get(atomics, slot(index, item, m)) == 1
    end)
  end

  @doc """
  ORs `from`'s bits into `into`'s array in place and returns `into`.

  Every slot set in `from` is set in `into`; slots already set in `into` are left alone.
  After merging, `into` reports `true` for every item that either filter contained.

  Both filters must have been created with identical `m` and `k` (in practice, the same
  arguments to `new/2`); otherwise their bit positions are incomparable and an
  `ArgumentError` is raised.

  ## Examples

      iex> a = ConcurrentBloomFilter.new(100, 0.01)
      iex> b = ConcurrentBloomFilter.new(100, 0.01)
      iex> ConcurrentBloomFilter.add(b, :from_b)
      iex> ConcurrentBloomFilter.merge(a, b)
      iex> ConcurrentBloomFilter.member?(a, :from_b)
      true

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{m: m, k: k, atomics: into_ref} = into, %__MODULE__{m: m, k: k} = from) do
    %__MODULE__{atomics: from_ref} = from

    Enum.each(1..m, fn position ->
      if :atomics.get(from_ref, position) == 1 do
        :atomics.put(into_ref, position, 1)
      end
    end)

    into
  end

  def merge(%__MODULE__{} = into, %__MODULE__{} = from) do
    raise ArgumentError,
          "cannot merge Bloom filters with different parameters: " <>
            "into has m=#{into.m}, k=#{into.k} but from has m=#{from.m}, k=#{from.k}"
  end

  # Maps the `index`-th derived hash of `item` onto a 1-based `:atomics` position.
  @spec slot(non_neg_integer(), term(), pos_integer()) :: pos_integer()
  defp slot(index, item, m) do
    :erlang.phash2({index, item}, m) + 1
  end

  # m = -ceil(n * ln(p) / (ln 2)^2), floored at one slot.
  @spec optimal_m(pos_integer(), float()) :: pos_integer()
  defp optimal_m(n, p) do
    m = -ceil(n * :math.log(p) / @ln2_squared)
    max(m, 1)
  end

  # k = round(m / n * ln 2), floored at one hash function.
  @spec optimal_k(pos_integer(), pos_integer()) :: pos_integer()
  defp optimal_k(m, n) do
    k = round(m / n * @ln2)
    max(k, 1)
  end
end