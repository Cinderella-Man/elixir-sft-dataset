# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `get` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `RefreshAheadCache` that stores key-value pairs with a TTL and **proactively refreshes** entries approaching expiration, so under steady traffic cache reads never miss.

The motivation: a plain TTL cache has a "cliff" at expiration — the first read after a key expires has to recompute the value from scratch while the caller waits. For expensive computations behind a cache (DB queries, external API calls), that latency spike is visible to users and causes thundering-herd problems when many requests hit expired entries at once. Refresh-ahead avoids the cliff: when an entry passes a configurable threshold (e.g. 80% through its TTL), a background task is spawned to re-run the value's loader, and the new result replaces the old entry atomically. Reads during the refresh window continue to return the existing (still-fresh) value.

I need these functions in the public API:

- `RefreshAheadCache.start_link(opts)` to start the process. Options:
  - `:name` — optional process registration
  - `:clock` — zero-arity function returning current time in ms (default `fn -> System.monotonic_time(:millisecond) end`)
  - `:sweep_interval_ms` — periodic hard-expiry sweep, milliseconds (default `60_000`); `:infinity` disables it
  - `:refresh_threshold` — a float in `(0.0, 1.0]` representing the fraction of the TTL after which a refresh is triggered (default `0.8`). At threshold `0.8` with a TTL of 1000ms, a read happening at `age >= 800ms` schedules a refresh.

- `RefreshAheadCache.put(server, key, value, ttl_ms, loader)` stores a key with its initial value, TTL, and a **loader function** — a zero-arity function that, when invoked, returns the next value to cache (possibly after a slow I/O call). The loader is stored alongside the value so the cache can call it again on refresh. If the key already exists, overwrite value, TTL, and loader. Returns `:ok`.

- `RefreshAheadCache.get(server, key)` retrieves a key. Behavior by state:
  - **Missing** — return `:miss`.
  - **Past hard expiry** (i.e. `now >= expires_at`) — delete the entry and return `:miss`. Lazy expiration on read, same as the original TTLCache.
  - **Past refresh threshold but not expired** — return `{:ok, value}` AND, if a refresh is not already in flight for this key, trigger one. The refresh runs asynchronously (see below). Reads continue returning the current value until the refresh completes.
  - **Below the refresh threshold** — return `{:ok, value}`, no refresh triggered.

- `RefreshAheadCache.delete(server, key)` removes a key. If a refresh is in flight for this key, the refresh's result (when it arrives) must be discarded — not applied to the cache, and not resurrected as a new entry. Returns `:ok` regardless.

- `RefreshAheadCache.stats(server)` returns `%{entries: non_neg_integer, refreshes_in_flight: non_neg_integer}` — useful for tests and observability.

**Async refresh machinery — the heart of this module:**

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

**Hard-expiry sweep**: every `sweep_interval_ms`, scan all entries and remove those with `expires_at <= now`. Sweep must NOT cancel in-flight refresh tasks for entries that were just swept — the refresh result will simply be discarded when it arrives and doesn't match a live entry.

A key-race you must handle correctly: if the user `put`s a new value for a key that has a refresh in flight, the old refresh's result must be discarded on arrival. The trick is that `put` should update the in-flight map appropriately — concretely, the simplest correct behavior is that `put` clears the in-flight entry for that key (so when the old refresh arrives, its `task_ref` doesn't match and its result is discarded).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- Sending the server process a bare `:sweep` message performs one sweep
  pass immediately — the same work the periodic timer performs.

- If `:refresh_threshold` is not a number in `(0.0, 1.0]` (e.g. `0.0` or
  `1.5`), `start_link/1` raises `ArgumentError` in the calling process —
  validate the option in `start_link/1` itself, before starting the GenServer
  (a failure inside `init/1` would surface to the caller as an exit, not a
  raise).

## The module with `get` missing

```elixir
defmodule RefreshAheadCache do
  @moduledoc """
  A GenServer-based TTL cache that proactively refreshes entries approaching
  expiration by running a user-supplied loader function in a background task.

  Each entry stores `{value, expires_at, ttl_ms, loader}`.  A `get/2` that
  observes `age >= refresh_threshold * ttl_ms` schedules a refresh (if none is
  already in flight for that key) and returns the current value.  When the
  refresh completes, its result replaces the entry with a fresh TTL.

  In-flight refreshes are tracked by a `make_ref()` token per key.  Results
  from background tasks are matched against the currently-tracked token; if
  the token has changed (due to `put/5`, `delete/2`, or a newer refresh),
  the result is discarded.

  ## Options

    * `:name`                – optional process registration
    * `:clock`               – `(-> integer())` current time in ms
    * `:sweep_interval_ms`   – hard-expiry sweep interval (default 60_000)
    * `:refresh_threshold`   – float in (0.0, 1.0] (default 0.8)

  """

  use GenServer

  defstruct [
    :clock,
    :sweep_interval_ms,
    :refresh_threshold,
    entries: %{},
    in_flight: %{}
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    refresh_threshold = Keyword.get(opts, :refresh_threshold, 0.8)

    unless is_number(refresh_threshold) and refresh_threshold > 0.0 and
             refresh_threshold <= 1.0 do
      raise ArgumentError,
            "refresh_threshold must be in (0.0, 1.0], got: #{inspect(refresh_threshold)}"
    end

    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec put(GenServer.server(), term(), term(), pos_integer(), (-> term())) :: :ok
  @doc """
  Stores `value` under `key` for `ttl_ms`, using `loader/0` to refresh the entry ahead
  of expiry. Returns `:ok`.
  """
  def put(server, key, value, ttl_ms, loader)
      when is_integer(ttl_ms) and ttl_ms > 0 and is_function(loader, 0) do
    GenServer.call(server, {:put, key, value, ttl_ms, loader})
  end

  def get(server, key) do
    # TODO
  end

  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key), do: GenServer.call(server, {:delete, key})

  @spec stats(GenServer.server()) :: %{
          entries: non_neg_integer(),
          refreshes_in_flight: non_neg_integer()
        }
  def stats(server), do: GenServer.call(server, :stats)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, 60_000)
    refresh_threshold = Keyword.get(opts, :refresh_threshold, 0.8)

    schedule_sweep(sweep_interval_ms)

    {:ok,
     %__MODULE__{
       clock: clock,
       sweep_interval_ms: sweep_interval_ms,
       refresh_threshold: refresh_threshold * 1.0
     }}
  end

  @impl true
  def handle_call({:put, key, value, ttl_ms, loader}, _from, state) do
    now = state.clock.()

    entry = %{
      value: value,
      expires_at: now + ttl_ms,
      ttl_ms: ttl_ms,
      loader: loader
    }

    # Invalidate any in-flight refresh for this key so a stale result can't
    # clobber the new put.
    new_in_flight = Map.delete(state.in_flight, key)

    {:reply, :ok,
     %{state | entries: Map.put(state.entries, key, entry), in_flight: new_in_flight}}
  end

  def handle_call({:get, key}, _from, state) do
    now = state.clock.()

    case Map.fetch(state.entries, key) do
      {:ok, entry} ->
        cond do
          # Hard expiry — evict lazily and miss.
          now >= entry.expires_at ->
            new_in_flight = Map.delete(state.in_flight, key)

            {:reply, :miss,
             %{
               state
               | entries: Map.delete(state.entries, key),
                 in_flight: new_in_flight
             }}

          # Past refresh threshold — trigger an async refresh if none running.
          should_refresh?(entry, now, state.refresh_threshold) and
              not Map.has_key?(state.in_flight, key) ->
            task_ref = spawn_refresh(key, entry.loader)
            new_in_flight = Map.put(state.in_flight, key, task_ref)
            {:reply, {:ok, entry.value}, %{state | in_flight: new_in_flight}}

          # Fresh enough OR refresh already in flight — just return value.
          true ->
            {:reply, {:ok, entry.value}, state}
        end

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok,
     %{
       state
       | entries: Map.delete(state.entries, key),
         in_flight: Map.delete(state.in_flight, key)
     }}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       entries: map_size(state.entries),
       refreshes_in_flight: map_size(state.in_flight)
     }, state}
  end

  # Refresh result: apply only if entry still exists AND task_ref still matches.
  @impl true
  def handle_info({:refresh_complete, key, task_ref, new_value}, state) do
    case {Map.fetch(state.entries, key), Map.fetch(state.in_flight, key)} do
      {{:ok, entry}, {:ok, ^task_ref}} ->
        now = state.clock.()
        updated = %{entry | value: new_value, expires_at: now + entry.ttl_ms}

        {:noreply,
         %{
           state
           | entries: Map.put(state.entries, key, updated),
             in_flight: Map.delete(state.in_flight, key)
         }}

      _ ->
        # Key gone, overwritten, or a newer refresh is in flight — discard.
        new_in_flight =
          case Map.fetch(state.in_flight, key) do
            {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
            _ -> state.in_flight
          end

        {:noreply, %{state | in_flight: new_in_flight}}
    end
  end

  def handle_info({:refresh_failed, key, task_ref, _reason}, state) do
    # Leave the old value in place; just clear the in-flight marker if still ours.
    new_in_flight =
      case Map.fetch(state.in_flight, key) do
        {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
        _ -> state.in_flight
      end

    {:noreply, %{state | in_flight: new_in_flight}}
  end

  def handle_info(:sweep, state) do
    now = state.clock.()

    pruned =
      state.entries
      |> Enum.reject(fn {_k, %{expires_at: e}} -> now >= e end)
      |> Map.new()

    new_in_flight =
      state.in_flight
      |> Enum.filter(fn {k, _ref} -> Map.has_key?(pruned, k) end)
      |> Map.new()

    schedule_sweep(state.sweep_interval_ms)

    {:noreply, %{state | entries: pruned, in_flight: new_in_flight}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Refresh machinery — runs outside the GenServer
  # ---------------------------------------------------------------------------

  defp spawn_refresh(key, loader) do
    task_ref = make_ref()
    parent = self()

    _ =
      Task.start_link(fn ->
        try do
          new_value = loader.()
          send(parent, {:refresh_complete, key, task_ref, new_value})
        rescue
          e -> send(parent, {:refresh_failed, key, task_ref, e})
        catch
          kind, reason -> send(parent, {:refresh_failed, key, task_ref, {kind, reason}})
        end
      end)

    task_ref
  end

  defp should_refresh?(entry, now, threshold) do
    age = now - (entry.expires_at - entry.ttl_ms)
    age >= threshold * entry.ttl_ms
  end

  defp schedule_sweep(:infinity), do: :ok

  defp schedule_sweep(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :sweep, ms)
  end
end
```

Give me only the complete implementation of `get` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
