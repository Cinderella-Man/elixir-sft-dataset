# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

# RefreshAheadCache — Specification

## Overview

This document specifies an Elixir GenServer module named `RefreshAheadCache` that stores key-value pairs with a TTL and **proactively refreshes** entries approaching expiration, so that under steady traffic cache reads never miss.

The motivation is as follows. A plain TTL cache has a "cliff" at expiration — the first read after a key expires has to recompute the value from scratch while the caller waits. For expensive computations behind a cache (DB queries, external API calls), that latency spike is visible to users and causes thundering-herd problems when many requests hit expired entries at once. Refresh-ahead avoids the cliff: when an entry passes a configurable threshold (e.g. 80% through its TTL), a background task is spawned to re-run the value's loader, and the new result replaces the old entry atomically. Reads during the refresh window continue to return the existing (still-fresh) value.

The complete module is to be delivered in a single file. It must use only the OTP standard library, with no external dependencies.

## API

The public API comprises the following functions.

- `RefreshAheadCache.start_link(opts)` starts the process. Options:
  - `:name` — optional process registration.
  - `:clock` — zero-arity function returning current time in ms (default `fn -> System.monotonic_time(:millisecond) end`).
  - `:sweep_interval_ms` — periodic hard-expiry sweep, milliseconds (default `60_000`); `:infinity` disables it.
  - `:refresh_threshold` — a float in `(0.0, 1.0]` representing the fraction of the TTL after which a refresh is triggered (default `0.8`). At threshold `0.8` with a TTL of 1000ms, a read happening at `age >= 800ms` schedules a refresh.

- `RefreshAheadCache.put(server, key, value, ttl_ms, loader)` stores a key with its initial value, TTL, and a **loader function** — a zero-arity function that, when invoked, returns the next value to cache (possibly after a slow I/O call). The loader is stored alongside the value so the cache can call it again on refresh. If the key already exists, it overwrites value, TTL, and loader. Returns `:ok`.

- `RefreshAheadCache.get(server, key)` retrieves a key. Its behavior by state is:
  - **Missing** — return `:miss`.
  - **Past hard expiry** (i.e. `now >= expires_at`) — delete the entry and return `:miss`. This is lazy expiration on read, the same as the original TTLCache.
  - **Past refresh threshold but not expired** — return `{:ok, value}` AND, if a refresh is not already in flight for this key, trigger one. The refresh runs asynchronously (see below). Reads continue returning the current value until the refresh completes.
  - **Below the refresh threshold** — return `{:ok, value}`, with no refresh triggered.

- `RefreshAheadCache.delete(server, key)` removes a key. If a refresh is in flight for this key, the refresh's result (when it arrives) must be discarded — not applied to the cache, and not resurrected as a new entry. Returns `:ok` regardless.

- `RefreshAheadCache.stats(server)` returns `%{entries: non_neg_integer, refreshes_in_flight: non_neg_integer}` — useful for tests and observability.

### Async refresh machinery — the heart of this module

When `get/2` observes that an entry has crossed the refresh threshold and no refresh is already running for that key, the GenServer must:

1. Mark the key as "refresh in flight" in its state so concurrent reads don't trigger duplicate refreshes.
2. Spawn a `Task.start_link` (or equivalent) that:
   - Calls the loader function in the spawned process (NOT inside the GenServer, so the server isn't blocked on I/O).
   - When the loader returns a value, sends `{:refresh_complete, key, task_ref, new_value}` to the GenServer.
   - If the loader raises or throws, sends `{:refresh_failed, key, task_ref, reason}` instead.
3. Associate the spawned task with a unique `task_ref` (e.g. `make_ref()`) and store it in the in-flight map: `%{key => task_ref}`.

The GenServer then handles:

- `{:refresh_complete, key, task_ref, new_value}` — apply the new value ONLY IF the key still exists AND the `task_ref` matches the currently-tracked in-flight ref for that key. Otherwise discard (the key was deleted, overwritten, or another refresh started — the result is stale). On a matching apply, update value and `expires_at = now + original_ttl_ms`, preserve the original loader, and clear the in-flight entry.

- `{:refresh_failed, key, task_ref, reason}` — just clear the in-flight entry (same `task_ref` match check). The old value remains in place; the next `get` past threshold will trigger a new refresh attempt.

The **original TTL** is preserved across refreshes — refreshing restarts the clock to `now + ttl_ms_original`, not `now + some_new_ttl`. Each entry therefore remembers its configured `ttl_ms` in state.

## Edge cases

**Hard-expiry sweep**: every `sweep_interval_ms`, the module scans all entries and removes those with `expires_at <= now`. The sweep must NOT cancel in-flight refresh tasks for entries that were just swept — the refresh result will simply be discarded when it arrives and doesn't match a live entry.

A key-race that must be handled correctly: if the user `put`s a new value for a key that has a refresh in flight, the old refresh's result must be discarded on arrival. The trick is that `put` should update the in-flight map appropriately — concretely, the simplest correct behavior is that `put` clears the in-flight entry for that key (so when the old refresh arrives, its `task_ref` doesn't match and its result is discarded).

Additional interface contract:

- Sending the server process a bare `:sweep` message performs one sweep pass immediately — the same work the periodic timer performs.

- If `:refresh_threshold` is not a number in `(0.0, 1.0]` (e.g. `0.0` or `1.5`), `start_link/1` raises `ArgumentError` in the calling process — the option is to be validated in `start_link/1` itself, before starting the GenServer (a failure inside `init/1` would surface to the caller as an exit, not a raise).
