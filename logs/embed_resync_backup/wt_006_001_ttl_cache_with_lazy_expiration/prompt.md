# Write the test harness

Module and original specification below. Produce the ExUnit harness that
verifies a correct implementation.

Hard requirements:
- Test module: `<Module>Test`, `use ExUnit.Case, async: false`.
- No `ExUnit.start()` (the evaluator owns startup).
- Self-contained single file: inline any fakes, clock Agents, and helpers.
- Full public API coverage plus the specification's edge cases.
- Compiles with zero warnings (`_`-prefix unused variables; float zero
  matches as `+0.0`/`-0.0`).

## Original specification

Write me an Elixir GenServer module called `TTLCache` that stores key-value pairs with per-key time-to-live (TTL) expiration, using lazy expiration on reads plus a periodic sweep for unread keys.

I need these functions in the public API:

- `TTLCache.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:sweep_interval_ms` option (default 60_000) controlling how often a periodic sweep runs to remove all expired entries. On success it returns `{:ok, pid}`.

- `TTLCache.put(server, key, value, ttl_ms)` which stores a key-value pair that expires after `ttl_ms` milliseconds from the time of insertion. The entry is live only while the current time (per `:clock`) is strictly before its expiration instant of insertion-time + `ttl_ms`; at or after that instant the key is expired. If the key already exists, overwrite both its value and its expiration. Returns `:ok`.

- `TTLCache.get(server, key)` which looks up a key. If the key exists and has not expired, return `{:ok, value}`. If the key does not exist or has expired, return `:miss`. Expired keys must be lazily deleted from internal state on read so they don't linger.

- `TTLCache.delete(server, key)` which explicitly removes a key regardless of whether it has expired. Returns `:ok` whether the key existed or not.

Each key is independent — putting or deleting key "a" must have no effect on key "b". A `put` with a new TTL on an existing key resets that key's expiration entirely based on the current time plus the new TTL.

You also need to prevent memory leaks from keys that are written but never read again. Use `Process.send_after` to schedule a `:sweep` message every `:sweep_interval_ms` milliseconds. When the sweep runs, remove all entries whose expiration time is in the past. The sweep should reschedule itself after completing. Handling a `:sweep` message must remove expired entries whether it arrived from the scheduled timer or was sent to the process directly, and must not disrupt subsequent `put`/`get`/`delete` operations.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- The `:sweep_interval_ms` option may also be `:infinity`, in which case the periodic
  timer is never scheduled — nothing runs automatically.

## Module under test

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
