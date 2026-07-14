# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule TTLCache do
  @moduledoc """
  A GenServer-based cache that stores key-value pairs with per-key TTL expiration.

  Expiration is enforced lazily on reads and periodically via a background sweep
  to prevent memory leaks from keys that are written but never read again.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Starts the cache process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Stores `value` under `key` with a TTL of `ttl_ms` milliseconds."
  @spec put(GenServer.server(), term(), term(), non_neg_integer()) :: :ok
  def put(server, key, value, ttl_ms) do
    GenServer.call(server, {:put, key, value, ttl_ms})
  end

  @doc "Retrieves the value for `key`, returning `{:ok, value}` or `:miss`."
  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  @doc "Deletes `key` from the cache. Always returns `:ok`."
  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key) do
    GenServer.call(server, {:delete, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_sweep_interval_ms 60_000

  defstruct [:clock, :sweep_interval_ms, entries: %{}]

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms)

    state = %__MODULE__{
      clock: clock,
      sweep_interval_ms: sweep_interval_ms
    }

    schedule_sweep(sweep_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl_ms}, _from, state) do
    expires_at = state.clock.() + ttl_ms
    entry = %{value: value, expires_at: expires_at}
    {:reply, :ok, %{state | entries: Map.put(state.entries, key, entry)}}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, %{value: value, expires_at: expires_at}} ->
        if state.clock.() < expires_at do
          {:reply, {:ok, value}, state}
        else
          {:reply, :miss, %{state | entries: Map.delete(state.entries, key)}}
        end

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, %{state | entries: Map.delete(state.entries, key)}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = state.clock.()

    pruned =
      state.entries
      |> Enum.reject(fn {_key, %{expires_at: expires_at}} -> now >= expires_at end)
      |> Map.new()

    schedule_sweep(state.sweep_interval_ms)

    {:noreply, %{state | entries: pruned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_sweep(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :sweep, interval_ms)
  end

  defp schedule_sweep(_), do: :ok
end
```

## New specification

Write me an Elixir GenServer module called `LRUCache` that stores key-value pairs with a fixed **maximum number of entries** and evicts the **least recently used** key when the cache is full.

The motivation: TTL-based caches bound memory by time, but many workloads need memory bounded by *count* instead — a cache of the 1000 most-active users, the 500 most-recent compiled templates, etc. With no natural TTL, eviction must be driven by access recency: when a new entry is inserted and the cache is at capacity, the key that was least recently read or written is dropped.

I need these functions in the public API:

- `LRUCache.start_link(opts)` to start the process. It should accept:
  - `:name` — optional process registration name
  - `:capacity` — required positive integer, the maximum number of entries the cache will hold
  - `:clock` — zero-arity function returning an integer (any monotonically-increasing unit; only ordering matters). Defaults to `fn -> System.monotonic_time() end`. The clock is used purely to timestamp accesses for LRU ordering — there is no TTL.

- `LRUCache.put(server, key, value)` which stores a key-value pair. If the key already exists, the value is overwritten and the access timestamp is updated (so the key becomes most-recently-used). If inserting would exceed `capacity`, the single least-recently-used entry is evicted **before** the new entry is inserted. Returns `:ok`.

- `LRUCache.get(server, key)` which looks up a key. If the key exists, return `{:ok, value}` and **update the key's access timestamp to the current clock value** so it becomes most-recently-used. If the key doesn't exist, return `:miss`. A `get` that hits must therefore mutate the GenServer's state — this is unavoidable for a correct LRU.

- `LRUCache.delete(server, key)` which removes a key. Returns `:ok` whether it existed or not.

- `LRUCache.size(server)` which returns the current number of entries as a non-negative integer. Never exceeds `capacity`.

- `LRUCache.keys_by_recency(server)` which returns all keys sorted from most-recently-used to least-recently-used. Useful for debugging and testing. Returns `[]` if the cache is empty.

**Eviction semantics you must get right:**

- A `put` on a key that already exists **never evicts another key**, because the entry count doesn't change. It just updates value and timestamp.
- A `put` on a new key when `size == capacity` evicts exactly **one** entry — the one with the smallest access timestamp — before inserting.
- Both `get` (on hit) and `put` (always) count as accesses that update the timestamp.
- `delete` does not count as an access; it just removes the entry.
- `capacity` of 0 is not allowed — `start_link` should refuse it.

**Implementation note**: storing entries as `%{key => %{value, access_ts}}` and scanning for the oldest on every eviction is O(n) per eviction. That's acceptable and what I want you to do — don't bring in an ordered map or DLL. Use `Enum.min_by` on the entries when you need to evict. What matters is that the LRU semantics are correct, not that eviction is O(log n). Tie-breaking when two entries have the same access_ts (should be rare with monotonic_time) can be arbitrary; do not pretend to handle it specially.

There is no periodic sweep and no TTL — with a fixed capacity, memory is bounded by construction. Do not use `Process.send_after`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- When `:capacity` is not a positive integer (e.g. `0` or `-1`), `start_link/1`
  raises `ArgumentError` in the calling process — validate the option in
  `start_link/1` itself, before starting the GenServer (a failure inside
  `init/1` would surface to the caller as an exit, not a raise).
