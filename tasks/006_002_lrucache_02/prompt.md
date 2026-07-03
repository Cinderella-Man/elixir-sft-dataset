Implement the GenServer `handle_call/3` callback for `LRUCache`. It has **five clauses**, one per request the public API issues. Every clause returns a `{:reply, reply, new_state}` tuple; several must mutate `state.entries`.

1. **`{:put, key, value}`** — store the pair. Read the current time with `state.clock.()` and build the entry `%{value: value, access_ts: now}`. Then:
   - If `key` is already present, overwrite it in place (updating value and timestamp). This does **not** change the entry count, so **never evict**.
   - If `key` is new and `map_size(state.entries) >= state.capacity`, evict the least-recently-used entry first using `evict_lru/1`, then insert the new entry.
   - If `key` is new and there is capacity to spare, just insert it.

   Reply with `:ok` and the updated state.

2. **`{:get, key}`** — look the key up with `Map.fetch/2`.
   - On hit, reply `{:ok, value}` **and** refresh that entry's `access_ts` to `state.clock.()` in the stored state (this mutation is required for correct LRU behavior).
   - On miss, reply `:miss` with the state unchanged.

3. **`{:delete, key}`** — remove the key with `Map.delete/2` (a no-op if absent, no timestamp change) and reply `:ok`.

4. **`:size`** — reply with `map_size(state.entries)`, state unchanged.

5. **`:keys_by_recency`** — reply with the keys sorted by `access_ts` from most- to least-recently-used (descending), state unchanged.

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
  def handle_call(request, from, state) do
    # TODO
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