# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir GenServer module called `SwrCache` that implements **Stale-While-Revalidate** caching with two independent freshness tiers.

The motivation: traditional TTL caches have a single cliff — past the TTL, the entry is gone and the next reader waits for a recompute. SWR (used by HTTP caches, Cloudflare, React Query, SWR.js) introduces a second tier: past `fresh_until` the entry is served as **stale** while a background revalidation recomputes it; past `stale_until` the entry is dropped entirely and becomes a hard miss. This lets fast paths serve traffic immediately with bounded staleness, while async revalidation keeps the cache hot. The distinction from refresh-ahead is semantic: SWR tells the caller the freshness of what they got, and the "stale" tier is bounded by its own timeout, not by a fraction of the fresh TTL.

I need these functions in the public API:

- `SwrCache.start_link(opts)`:
  - `:name` — optional process registration
  - `:clock` — `(-> integer())` current time in ms (default `fn -> System.monotonic_time(:millisecond) end`)
  - `:sweep_interval_ms` — periodic sweep of fully-expired entries, in ms (default `60_000`; `:infinity` disables)

- `SwrCache.put(server, key, value, fresh_ms, stale_ms, loader)` where:
  - `fresh_ms` is how long the entry is considered **fresh** (served directly, no revalidation)
  - `stale_ms` is how much additional time past `fresh_until` the entry is served as **stale** while revalidation runs. The entry is hard-deleted at `fresh_until + stale_ms`.
  - `loader` is a zero-arity function invoked asynchronously to produce a new value during revalidation. Its result replaces the entry with a new `fresh_ms` clock.
  - Both `fresh_ms` and `stale_ms` must be positive integers. If the key already exists, all four — value, fresh_ms, stale_ms, loader — are overwritten.

  Returns `:ok`.

- `SwrCache.get(server, key)` with a three-way return shape:
  - `{:ok, value, :fresh}` — within the fresh window, no revalidation triggered
  - `{:ok, value, :stale}` — within the stale window; a revalidation is triggered if not already in flight for this key, and the current (stale) value is returned
  - `:miss` — no entry, or the entry is past its hard-expiry (`fresh_until + stale_ms`). In the latter case the entry is lazily evicted on this read.

  The three-way return is deliberate — callers often want to distinguish a fresh value from a stale-but-acceptable one (e.g. to show a "refreshing..." indicator, or to skip a stale value and force a synchronous recompute). This is the defining API shape of SWR vs a plain TTL cache.

- `SwrCache.delete(server, key)` removes the entry and invalidates any in-flight revalidation for that key (i.e. the revalidation's result, when it arrives, will be discarded). Returns `:ok` regardless of existence.

- `SwrCache.stats(server)` returns `%{entries: non_neg_integer, revalidations_in_flight: non_neg_integer}`.

**Revalidation machinery** (similar to refresh-ahead but with SWR semantics):

When `get/2` observes that an entry is in the stale window AND no revalidation is already in flight for that key:

1. Mark the key as "revalidation in flight" with a unique `task_ref`.
2. Spawn a task that calls the loader and sends `{:revalidate_complete, key, task_ref, new_value}` to the GenServer, or `{:revalidate_failed, key, task_ref, reason}` on error/raise/throw.

The GenServer handles the result:

- `{:revalidate_complete, key, task_ref, new_value}` — if the key still exists AND the in-flight ref still matches, apply the new value with a **fresh `fresh_ms` and `stale_ms` drawn from the current entry** (revalidation preserves the original tier durations). Clear the in-flight marker. Otherwise discard.

- `{:revalidate_failed, key, task_ref, reason}` — clear the in-flight marker if it matches. The entry stays in its current state — still stale, which means the next stale read will trigger another revalidation.

**Hard expiry vs stale tier**: careful math. With `fresh_ms = 1000` and `stale_ms = 2000`, a put at t=0 yields:

- t ∈ [0, 1000): fresh — return `{:ok, value, :fresh}`, no revalidation
- t ∈ [1000, 3000): stale — return `{:ok, value, :stale}`, trigger revalidation if not in flight
- t ≥ 3000: hard expired — return `:miss`, lazily evict

A `put` that overwrites invalidates any in-flight revalidation (same mechanism as the refresh-ahead variant) so a stale result can't clobber the new value.

The periodic sweep removes only fully-expired (past-stale) entries. Entries in the stale window are kept in state because the next reader triggers a revalidation from them. A stale entry with a failed revalidation is NOT eagerly dropped by sweep — it remains until it passes hard expiry.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Module under test

```elixir
defmodule SwrCache do
  @moduledoc """
  A GenServer-based Stale-While-Revalidate cache.

  Each entry has two independent windows:

    * **fresh**  – `[put_at, put_at + fresh_ms)` — serve directly, no
      revalidation; `get/2` returns `{:ok, value, :fresh}`.
    * **stale**  – `[put_at + fresh_ms, put_at + fresh_ms + stale_ms)` —
      serve the (stale) value and asynchronously trigger a revalidation
      via the stored loader function; `get/2` returns
      `{:ok, value, :stale}`.

  Past the stale window the entry is hard-expired: `get/2` returns `:miss`
  and evicts the entry lazily.  A periodic sweep also removes past-stale
  entries in bulk.

  Revalidation runs in a `Task.start_link/1` so the GenServer isn't blocked
  on the loader.  In-flight tokens (`make_ref/0`) gate application of results
  so a `delete/2` or a later `put/6` invalidates in-flight revalidations —
  when the old result arrives it is discarded.

  ## Options

    * `:name`              – optional process registration
    * `:clock`             – `(-> integer())` current time in ms
    * `:sweep_interval_ms` – periodic hard-expiry sweep (default 60_000;
                             `:infinity` disables)

  """

  use GenServer

  defstruct [
    :clock,
    :sweep_interval_ms,
    entries: %{},
    in_flight: %{}
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec put(GenServer.server(), term(), term(), pos_integer(), pos_integer(), (-> term())) :: :ok
  def put(server, key, value, fresh_ms, stale_ms, loader)
      when is_integer(fresh_ms) and fresh_ms > 0 and
             is_integer(stale_ms) and stale_ms > 0 and
             is_function(loader, 0) do
    GenServer.call(server, {:put, key, value, fresh_ms, stale_ms, loader})
  end

  @spec get(GenServer.server(), term()) ::
          {:ok, term(), :fresh} | {:ok, term(), :stale} | :miss
  def get(server, key), do: GenServer.call(server, {:get, key})

  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key), do: GenServer.call(server, {:delete, key})

  @spec stats(GenServer.server()) ::
          %{entries: non_neg_integer(), revalidations_in_flight: non_neg_integer()}
  def stats(server), do: GenServer.call(server, :stats)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, 60_000)

    schedule_sweep(sweep_interval_ms)

    {:ok, %__MODULE__{clock: clock, sweep_interval_ms: sweep_interval_ms}}
  end

  @impl true
  def handle_call({:put, key, value, fresh_ms, stale_ms, loader}, _from, state) do
    now = state.clock.()

    entry = %{
      value: value,
      fresh_until: now + fresh_ms,
      hard_expires_at: now + fresh_ms + stale_ms,
      fresh_ms: fresh_ms,
      stale_ms: stale_ms,
      loader: loader
    }

    # Invalidate any in-flight revalidation so a stale result can't clobber.
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
          now >= entry.hard_expires_at ->
            {:reply, :miss,
             %{
               state
               | entries: Map.delete(state.entries, key),
                 in_flight: Map.delete(state.in_flight, key)
             }}

          # Still fresh — serve directly, no revalidation.
          now < entry.fresh_until ->
            {:reply, {:ok, entry.value, :fresh}, state}

          # Stale window — serve stale, trigger revalidation if not in flight.
          true ->
            new_state =
              if Map.has_key?(state.in_flight, key) do
                state
              else
                task_ref = spawn_revalidate(key, entry.loader)
                %{state | in_flight: Map.put(state.in_flight, key, task_ref)}
              end

            {:reply, {:ok, entry.value, :stale}, new_state}
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
     %{entries: map_size(state.entries), revalidations_in_flight: map_size(state.in_flight)},
     state}
  end

  @impl true
  def handle_info({:revalidate_complete, key, task_ref, new_value}, state) do
    case {Map.fetch(state.entries, key), Map.fetch(state.in_flight, key)} do
      {{:ok, entry}, {:ok, ^task_ref}} ->
        now = state.clock.()

        updated = %{
          entry
          | value: new_value,
            fresh_until: now + entry.fresh_ms,
            hard_expires_at: now + entry.fresh_ms + entry.stale_ms
        }

        {:noreply,
         %{
           state
           | entries: Map.put(state.entries, key, updated),
             in_flight: Map.delete(state.in_flight, key)
         }}

      _ ->
        # Stale result from a no-longer-tracked revalidation.
        new_in_flight =
          case Map.fetch(state.in_flight, key) do
            {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
            _ -> state.in_flight
          end

        {:noreply, %{state | in_flight: new_in_flight}}
    end
  end

  def handle_info({:revalidate_failed, key, task_ref, _reason}, state) do
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
      |> Enum.reject(fn {_k, %{hard_expires_at: h}} -> now >= h end)
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
  # Revalidation — runs outside the GenServer
  # ---------------------------------------------------------------------------

  defp spawn_revalidate(key, loader) do
    task_ref = make_ref()
    parent = self()

    _ =
      Task.start_link(fn ->
        try do
          new_value = loader.()
          send(parent, {:revalidate_complete, key, task_ref, new_value})
        rescue
          e -> send(parent, {:revalidate_failed, key, task_ref, e})
        catch
          kind, reason -> send(parent, {:revalidate_failed, key, task_ref, {kind, reason}})
        end
      end)

    task_ref
  end

  defp schedule_sweep(:infinity), do: :ok
  defp schedule_sweep(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :sweep, ms)
  end
end
```
