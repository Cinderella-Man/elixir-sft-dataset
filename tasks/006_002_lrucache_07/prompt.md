# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `delete` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `delete` missing

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

  def delete(server, key) do
    # TODO
  end

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

Give me only the complete implementation of `delete` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
