# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule LRUCache do
  @moduledoc """
  A GenServer-based cache with a fixed maximum number of entries and
  least-recently-used eviction.

  Each entry carries an access timestamp drawn from an injectable clock.
  On every `get/2` hit and every `put/3`, the entry's timestamp is refreshed
  to the current clock value; `put/3` that would overflow capacity evicts
  the entry with the smallest timestamp.

  No TTL, no periodic sweep: memory is bounded by `capacity` by construction.

  ## Options

    * `:name`      – optional process registration
    * `:capacity`  – required positive integer (max entries)
    * `:clock`     – `(-> integer())` returning a monotonically-increasing
                     value in any unit (default `&System.monotonic_time/0`)

  ## Examples

      iex> {:ok, pid} = LRUCache.start_link(capacity: 2)
      iex> LRUCache.put(pid, :a, 1)
      :ok
      iex> LRUCache.put(pid, :b, 2)
      :ok
      iex> LRUCache.put(pid, :c, 3)  # evicts :a
      :ok
      iex> LRUCache.get(pid, :a)
      :miss

  """

  use GenServer

  defstruct [:clock, :capacity, entries: %{}]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    capacity = Keyword.fetch!(opts, :capacity)

    unless is_integer(capacity) and capacity > 0 do
      raise ArgumentError, ":capacity must be a positive integer, got: #{inspect(capacity)}"
    end

    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Stores `value` under `key`, evicting the LRU entry when full. Returns `:ok`."
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(server, key, value), do: GenServer.call(server, {:put, key, value})

  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key), do: GenServer.call(server, {:get, key})

  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key), do: GenServer.call(server, {:delete, key})

  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server), do: GenServer.call(server, :size)

  @spec keys_by_recency(GenServer.server()) :: [term()]
  def keys_by_recency(server), do: GenServer.call(server, :keys_by_recency)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, &System.monotonic_time/0)
    capacity = Keyword.fetch!(opts, :capacity)

    {:ok, %__MODULE__{clock: clock, capacity: capacity}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    now = state.clock.()
    entry = %{value: value, access_ts: now}

    entries =
      cond do
        # Key already present — overwrite, no eviction, size unchanged.
        Map.has_key?(state.entries, key) ->
          Map.put(state.entries, key, entry)

        # New key, cache at capacity — evict LRU first.
        map_size(state.entries) >= state.capacity ->
          state.entries
          |> evict_lru()
          |> Map.put(key, entry)

        # New key, capacity available.
        true ->
          Map.put(state.entries, key, entry)
      end

    {:reply, :ok, %{state | entries: entries}}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, %{value: value} = entry} ->
        # Refresh access timestamp — LRU correctness requires this mutation.
        updated = %{entry | access_ts: state.clock.()}
        {:reply, {:ok, value}, %{state | entries: Map.put(state.entries, key, updated)}}

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, %{state | entries: Map.delete(state.entries, key)}}
  end

  def handle_call(:size, _from, state) do
    {:reply, map_size(state.entries), state}
  end

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.entries
      |> Enum.sort_by(fn {_k, %{access_ts: ts}} -> ts end, :desc)
      |> Enum.map(fn {k, _} -> k end)

    {:reply, keys, state}
  end

  # ---------------------------------------------------------------------------
  # Eviction — O(n) scan for the smallest access_ts
  # ---------------------------------------------------------------------------

  defp evict_lru(entries) when map_size(entries) == 0, do: entries

  defp evict_lru(entries) do
    {lru_key, _} = Enum.min_by(entries, fn {_k, %{access_ts: ts}} -> ts end)
    Map.delete(entries, lru_key)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule LRUCacheTest do
  use ExUnit.Case, async: false

  # --- Deterministic monotonically-increasing clock ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    # Every call to `now/0` returns a strictly-greater value — this models
    # a true monotonic clock and makes access ordering deterministic.
    def now do
      Agent.get_and_update(__MODULE__, fn n -> {n, n + 1} end)
    end

    def set(n), do: Agent.update(__MODULE__, fn _ -> n end)
    def current, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} = LRUCache.start_link(capacity: 3, clock: &Clock.now/0)

    %{lru: pid}
  end

  # -------------------------------------------------------
  # Basic put/get/delete
  # -------------------------------------------------------

  test "put / get round-trip", %{lru: c} do
    :ok = LRUCache.put(c, :a, 1)
    :ok = LRUCache.put(c, :b, 2)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
  end

  test "get on a missing key returns :miss", %{lru: c} do
    assert :miss = LRUCache.get(c, :nope)
  end

  test "delete removes the key", %{lru: c} do
    LRUCache.put(c, :a, 1)
    :ok = LRUCache.delete(c, :a)
    assert :miss = LRUCache.get(c, :a)
  end

  test "delete on missing key returns :ok", %{lru: c} do
    assert :ok = LRUCache.delete(c, :ghost)
  end

  # -------------------------------------------------------
  # Capacity enforcement
  # -------------------------------------------------------

  test "size never exceeds capacity", %{lru: c} do
    # TODO
  end

  test "start_link rejects zero or negative capacity" do
    assert_raise ArgumentError, fn -> LRUCache.start_link(capacity: 0) end
    assert_raise ArgumentError, fn -> LRUCache.start_link(capacity: -1) end
  end

  # -------------------------------------------------------
  # LRU eviction — the defining property
  # -------------------------------------------------------

  test "new put evicts the least-recently-used entry", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Cache is full.  Inserting :d must evict :a (oldest).
    LRUCache.put(c, :d, 4)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  test "get refreshes access timestamp — key becomes most-recently-used", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Touch :a so it's MRU; oldest is now :b
    assert {:ok, 1} = LRUCache.get(c, :a)

    # Inserting :d now must evict :b, not :a
    LRUCache.put(c, :d, 4)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  test "put on an existing key never evicts another key", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Overwriting :a should NOT evict :b or :c
    LRUCache.put(c, :a, 99)

    assert LRUCache.size(c) == 3
    assert {:ok, 99} = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
  end

  test "put on an existing key updates both value AND access timestamp", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Overwrite :a — makes it MRU, oldest is now :b
    LRUCache.put(c, :a, 99)

    # Next new-key insert must evict :b
    LRUCache.put(c, :d, 4)

    assert {:ok, 99} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
  end

  test "missing get does NOT refresh anything", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # A miss shouldn't change anything
    assert :miss = LRUCache.get(c, :nope)

    # Oldest is still :a, so this evicts :a
    LRUCache.put(c, :d, 4)
    assert :miss = LRUCache.get(c, :a)
  end

  test "delete does NOT refresh timestamps and allows future insert without eviction", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    LRUCache.delete(c, :b)
    assert LRUCache.size(c) == 2

    # Capacity is 3; we have 2 entries; inserting :d should not evict anything
    LRUCache.put(c, :d, 4)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  # -------------------------------------------------------
  # keys_by_recency inspection
  # -------------------------------------------------------

  test "keys_by_recency returns MRU first, LRU last", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    assert [:c, :b, :a] = LRUCache.keys_by_recency(c)

    LRUCache.get(c, :a)
    assert [:a, :c, :b] = LRUCache.keys_by_recency(c)

    LRUCache.put(c, :b, 99)
    assert [:b, :a, :c] = LRUCache.keys_by_recency(c)
  end

  # -------------------------------------------------------
  # Longer trace
  # -------------------------------------------------------

  test "longer sequence produces the expected LRU evictions" do
    # Clock is already started by setup — reset it instead of starting again.
    Clock.set(0)

    {:ok, c} = LRUCache.start_link(capacity: 3, clock: &Clock.now/0)

    # Standard LRU textbook trace.
    # [:a]
    LRUCache.put(c, :a, 1)
    # [:b, :a]
    LRUCache.put(c, :b, 2)
    # [:c, :b, :a]
    LRUCache.put(c, :c, 3)
    # [:a, :c, :b]
    LRUCache.get(c, :a)
    # evicts :b → [:d, :a, :c]
    LRUCache.put(c, :d, 4)
    # [:c, :d, :a]
    LRUCache.get(c, :c)
    # evicts :a → [:e, :c, :d]
    LRUCache.put(c, :e, 5)

    assert :miss = LRUCache.get(c, :b)
    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert {:ok, 5} = LRUCache.get(c, :e)
  end

  test "keys_by_recency returns empty list for an empty cache", %{lru: c} do
    assert [] = LRUCache.keys_by_recency(c)
  end

  test "capacity of one evicts the sole entry when a new key is inserted" do
    {:ok, c} = LRUCache.start_link(capacity: 1, clock: &Clock.now/0)

    :ok = LRUCache.put(c, :a, 1)
    :ok = LRUCache.put(c, :b, 2)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert LRUCache.size(c) == 1
  end

  test "start_link registers the process under the given :name" do
    name = :lru_named_registration_test

    {:ok, _pid} = LRUCache.start_link(capacity: 3, name: name, clock: &Clock.now/0)

    :ok = LRUCache.put(name, :a, 1)
    assert {:ok, 1} = LRUCache.get(name, :a)
    assert LRUCache.size(name) == 1
  end

  # -------------------------------------------------------
  # Default clock (:clock option omitted)
  # -------------------------------------------------------

  # Blocks until the system monotonic clock has advanced past its current
  # reading, so each subsequent cache operation is stamped strictly later
  # than every operation issued before the call.
  defp await_monotonic_tick do
    spin_past(System.monotonic_time())
  end

  defp spin_past(t) do
    if System.monotonic_time() > t, do: :ok, else: spin_past(t)
  end

  test "omitting :clock uses the default monotonic clock for recency ordering" do
    {:ok, c} = LRUCache.start_link(capacity: 3)

    :ok = LRUCache.put(c, :a, 1)
    await_monotonic_tick()
    :ok = LRUCache.put(c, :b, 2)
    await_monotonic_tick()
    :ok = LRUCache.put(c, :c, 3)
    await_monotonic_tick()

    # Writes alone order the keys most-recently-used first.
    assert [:c, :b, :a] = LRUCache.keys_by_recency(c)

    # A hit refreshes :a, making it MRU and leaving :b as the oldest entry.
    assert {:ok, 1} = LRUCache.get(c, :a)
    await_monotonic_tick()
    assert [:a, :c, :b] = LRUCache.keys_by_recency(c)

    # Inserting a fourth key at capacity evicts exactly the oldest entry.
    :ok = LRUCache.put(c, :d, 4)

    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 1} = LRUCache.get(c, :a)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert LRUCache.size(c) == 3
  end
end
```
