# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`new/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `new/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `new/2` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
