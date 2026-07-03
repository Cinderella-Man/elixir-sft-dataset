Implement the `handle_call/3` GenServer callback. This callback has **four clauses**,
one per public API operation. All four operate on the `%SwrCache{}` struct state, whose
`:clock` field is a zero-arity function returning the current time in ms, `:entries` is a
map of `key => entry`, and `:in_flight` is a map of `key => task_ref`. Each entry is a map
with `:value`, `:fresh_until`, `:hard_expires_at`, `:fresh_ms`, `:stale_ms`, and `:loader`.

- `{:put, key, value, fresh_ms, stale_ms, loader}` — read the current time via
  `state.clock.()`, build an entry whose `fresh_until` is `now + fresh_ms` and whose
  `hard_expires_at` is `now + fresh_ms + stale_ms` (also storing `fresh_ms`, `stale_ms`,
  and `loader` for later revalidation). Insert it into `entries`, and **invalidate any
  in-flight revalidation** for this key by deleting it from `in_flight` so a pending stale
  result can't clobber the freshly-put value. Reply `:ok`.

- `{:get, key}` — read the current time and look up the key in `entries`. On a miss, reply
  `:miss` unchanged. On a hit, decide by time window:
    * `now >= hard_expires_at` — hard-expired: lazily evict the entry (and any in-flight
      marker) and reply `:miss`.
    * `now < fresh_until` — fresh: reply `{:ok, value, :fresh}` with unchanged state.
    * otherwise — stale: reply `{:ok, value, :stale}`, and if no revalidation is already
      in flight for this key, spawn one via `spawn_revalidate/2` and record its `task_ref`
      in `in_flight`.

- `{:delete, key}` — remove the key from both `entries` and `in_flight` (invalidating any
  in-flight revalidation) and reply `:ok` regardless of whether it existed.

- `:stats` — reply with `%{entries: map_size(entries), revalidations_in_flight:
  map_size(in_flight)}`, state unchanged.

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
    # TODO
  end

  def handle_call({:get, key}, _from, state) do
    # TODO
  end

  def handle_call({:delete, key}, _from, state) do
    # TODO
  end

  def handle_call(:stats, _from, state) do
    # TODO
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