Implement the `handle_info/2` GenServer callbacks for `SwrCache`. This callback
handles the asynchronous messages that drive Stale-While-Revalidate behaviour:
revalidation results delivered by spawned loader tasks, the periodic hard-expiry
sweep, and any unrecognised message. It must cover four message shapes:

1. `{:revalidate_complete, key, task_ref, new_value}` — a revalidation task
   finished successfully. Apply the new value **only if** the key still exists
   in `entries` AND the in-flight token for that key still matches `task_ref`.
   When applying, read the current entry and rebuild its windows against a fresh
   `now = state.clock.()`: set `value` to `new_value`, `fresh_until` to
   `now + entry.fresh_ms`, and `hard_expires_at` to
   `now + entry.fresh_ms + entry.stale_ms` (revalidation preserves the entry's
   original tier durations). Then clear the in-flight marker for the key. If the
   key is gone or the ref no longer matches, the result is stale: discard the
   value but still clear the in-flight marker **only if** it matches this
   `task_ref` (a mismatching ref belongs to a newer revalidation and must be
   left untouched).

2. `{:revalidate_failed, key, task_ref, reason}` — a revalidation task errored,
   raised, or threw. Leave the entry exactly as it is (still stale, so the next
   stale read triggers another revalidation) and clear the in-flight marker
   **only if** it matches this `task_ref`.

3. `:sweep` — the periodic hard-expiry sweep. Compute `now`, keep only entries
   whose `hard_expires_at` is still in the future (`now < hard_expires_at`; drop
   the rest), then prune `in_flight` down to keys that survived. Reschedule the
   next sweep via `schedule_sweep(state.sweep_interval_ms)` and update the state
   with the pruned maps.

4. any other message — ignore it and leave the state unchanged.

All clauses return the standard `{:noreply, state}` shape.

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
  def handle_info(msg, state) do
    # TODO
  end

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