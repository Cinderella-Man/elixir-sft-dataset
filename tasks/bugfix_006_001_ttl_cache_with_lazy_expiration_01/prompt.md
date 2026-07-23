# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# TTLCache — GenServer key-value store with per-key TTL expiration

Implement an Elixir GenServer module `TTLCache` for key-value pairs with per-key time-to-live (TTL) expiration, using lazy expiration on reads plus a periodic sweep for unread keys. Deliver the complete module in a single file. Use only the OTP standard library — no external dependencies.

**Expiration model**
- An entry inserted at insertion-time with `ttl_ms` expires at insertion-time + `ttl_ms`.
- The entry is live only while the current time (per `:clock`) is strictly before that expiration instant; at or after that instant the key is expired.
- Keys are independent: putting or deleting key "a" must have no effect on key "b".
- A `put` with a new TTL on an existing key resets that key's expiration entirely, based on the current time plus the new TTL.

**Public API — `TTLCache.start_link(opts)`**
- Starts the process; returns `{:ok, pid}` on success.
- Accepts `:clock`, a zero-arity function returning the current time in milliseconds. Default: `fn -> System.monotonic_time(:millisecond) end`.
- Accepts `:name` for process registration.
- Accepts `:sweep_interval_ms` (default 60_000) controlling how often the periodic sweep runs to remove all expired entries.
- `:sweep_interval_ms` may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

**Public API — `TTLCache.put(server, key, value, ttl_ms)`**
- Stores a key-value pair that expires after `ttl_ms` milliseconds from the time of insertion.
- If the key already exists, overwrite both its value and its expiration.
- Returns `:ok`.

**Public API — `TTLCache.get(server, key)`**
- If the key exists and has not expired, return `{:ok, value}`.
- If the key does not exist or has expired, return `:miss`.
- Expired keys must be lazily deleted from internal state on read so they don't linger.

**Public API — `TTLCache.delete(server, key)`**
- Explicitly removes a key regardless of whether it has expired.
- Returns `:ok` whether the key existed or not.

**Periodic sweep**
- Prevent memory leaks from keys that are written but never read again.
- Use `Process.send_after` to schedule a `:sweep` message every `:sweep_interval_ms` milliseconds.
- When the sweep runs, remove all entries whose expiration time is in the past.
- The sweep must reschedule itself after completing.
- Handling a `:sweep` message must remove expired entries whether it arrived from the scheduled timer or was sent to the process directly, and must not disrupt subsequent `put`/`get`/`delete` operations.

## The buggy module

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

    {:error, state}
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

## Failing test report

```
19 of 19 test(s) failed:

  * test get returns :miss for a key that was never set
      no match of right hand side value:
      
          {:error,
           %TTLCache{
             clock: &TTLCacheTest.Clock.now/0,
             sweep_interval_ms: :infinity,
             entries: %{}
           }}
      

  * test put then get returns the stored value
      no match of right hand side value:
      
          {:error,
           %TTLCache{
             clock: &TTLCacheTest.Clock.now/0,
             sweep_interval_ms: :infinity,
             entries: %{}
           }}
      

  * test put overwrites an existing key
      no match of right hand side value:
      
          {:error,
           %TTLCache{
             clock: &TTLCacheTest.Clock.now/0,
             sweep_interval_ms: :infinity,
             entries: %{}
           }}
      

  * test stores various Elixir terms as values
      no match of right hand side value:
      
          {:error,
           %TTLCache{
             clock: &TTLCacheTest.Clock.now/0,
             sweep_interval_ms: :infinity,
             entries: %{}
           }}
      

  (…15 more)
```
