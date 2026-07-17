# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

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

  @doc "Stores `value` under `key` with fresh/stale TTLs and a `loader`. Returns `:ok`."
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

## Test harness — implement the `# TODO` test

```elixir
defmodule SwrCacheTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  defmodule Loader do
    use Agent

    def start_link(values) do
      Agent.start_link(fn -> %{values: values, calls: 0} end, name: __MODULE__)
    end

    def next_value do
      Agent.get_and_update(__MODULE__, fn s ->
        {v, rest} =
          case s.values do
            [v | rest] -> {v, rest}
            [] -> {:no_more_values, []}
          end

        {v, %{s | values: rest, calls: s.calls + 1}}
      end)
    end

    def slow_next_value(sleep_ms) do
      Process.sleep(sleep_ms)
      next_value()
    end

    def calls, do: Agent.get(__MODULE__, & &1.calls)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      SwrCache.start_link(
        clock: &Clock.now/0,
        sweep_interval_ms: :infinity
      )

    %{c: pid}
  end

  defp wait_for_idle(c, timeout_ms \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fn ->
      case SwrCache.stats(c) do
        %{revalidations_in_flight: 0} -> :idle
        _ -> :busy
      end
    end)
    |> Enum.reduce_while(nil, fn
      :idle, _ ->
        {:halt, :ok}

      :busy, _ ->
        if System.monotonic_time(:millisecond) > deadline do
          {:halt, :timeout}
        else
          Process.sleep(5)
          {:cont, nil}
        end
    end)
  end

  # -------------------------------------------------------
  # Three-way return shape
  # -------------------------------------------------------

  test "fresh window returns {:ok, value, :fresh}", %{c: c} do
    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> :should_not_be_called end)

    assert {:ok, :v1, :fresh} = SwrCache.get(c, :a)

    Clock.advance(999)
    assert {:ok, :v1, :fresh} = SwrCache.get(c, :a)
  end

  test "stale window returns {:ok, value, :stale}", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
  end

  test "past hard expiry returns :miss and evicts", %{c: c} do
    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> :never end)

    Clock.advance(3_000)
    assert :miss = SwrCache.get(c, :a)
    assert %{entries: 0} = SwrCache.stats(c)
  end

  test "missing key returns :miss", %{c: c} do
    assert :miss = SwrCache.get(c, :nope)
  end

  # -------------------------------------------------------
  # Revalidation trigger — the defining behavior
  # -------------------------------------------------------

  test "stale read triggers revalidation; later reads see new value", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    # Enter stale window
    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1

    # New value is :v2, and since revalidation happened at t=1000, it's fresh
    # until t=2000.
    assert {:ok, :v2, :fresh} = SwrCache.get(c, :a)
  end

  test "fresh reads do NOT trigger revalidation", %{c: c} do
    start_supervised!({Loader, [:never_called]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    # Read 5 times well within the fresh window
    for _ <- 1..5, do: assert({:ok, :v1, :fresh} = SwrCache.get(c, :a))

    :ok = wait_for_idle(c)
    assert Loader.calls() == 0
  end

  test "concurrent stale reads trigger only ONE revalidation", %{c: c} do
    # TODO
  end

  # -------------------------------------------------------
  # Revalidation resets BOTH fresh and stale windows
  # -------------------------------------------------------

  test "successful revalidation gives new full fresh+stale budget", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    Clock.advance(1_500)
    SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    # Revalidation happened at t=1500 so fresh until t=2500, stale until t=4500
    # t=2499
    Clock.advance(999)
    assert {:ok, :v2, :fresh} = SwrCache.get(c, :a)

    # t=2501
    Clock.advance(2)
    assert {:ok, :v2, :stale} = SwrCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Failed revalidation leaves entry stale (reread triggers retry)
  # -------------------------------------------------------

  test "failed revalidation leaves entry in place; next stale read retries", %{c: c} do
    # Loader that raises — but after a retry, returns a value
    start_supervised!({Loader, [:from_retry]})

    counter = :counters.new(1, [])
    :counters.put(counter, 1, 0)

    loader = fn ->
      :counters.add(counter, 1, 1)

      if :counters.get(counter, 1) == 1 do
        raise "first call always fails"
      else
        Loader.next_value()
      end
    end

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, loader)

    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    # Failed revalidation → entry unchanged (still the original :v1, still stale)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    assert {:ok, :from_retry, :fresh} = SwrCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Delete invalidates in-flight revalidation
  # -------------------------------------------------------

  test "delete during in-flight revalidation discards the result", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok =
      SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(1_000)
    # triggers slow revalidation
    SwrCache.get(c, :a)

    SwrCache.delete(c, :a)

    :ok = wait_for_idle(c)
    assert :miss = SwrCache.get(c, :a)
    assert %{entries: 0} = SwrCache.stats(c)
  end

  # -------------------------------------------------------
  # Put during in-flight revalidation wins
  # -------------------------------------------------------

  test "put during revalidation: revalidation result must not clobber", %{c: c} do
    start_supervised!({Loader, [:from_loader]})

    :ok =
      SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(1_000)
    # trigger slow revalidation
    SwrCache.get(c, :a)

    # User puts a new value before the revalidation completes
    SwrCache.put(c, :a, :user_set, 500, 1_000, fn -> :ignored end)

    :ok = wait_for_idle(c)

    # The user's put must win — value AND the fresh window is from the put's time
    assert {:ok, :user_set, :fresh} = SwrCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Sweep removes past-stale entries only
  # -------------------------------------------------------

  test "sweep removes entries past stale window, keeps stale-but-live entries", %{c: c} do
    # Reset Clock to 0 (setup already started it)
    Clock.set(0)

    # hard expires at 300
    :ok = SwrCache.put(c, :a, 1, 100, 200, fn -> :_ end)
    # hard expires at 3000
    :ok = SwrCache.put(c, :b, 2, 200, 2_800, fn -> :_ end)

    Clock.advance(500)
    send(c, :sweep)

    # Only the past-stale entry :a is dropped; the stale-but-live :b survives.
    assert %{entries: 1} = SwrCache.stats(c)

    assert :miss = SwrCache.get(c, :a)
    # :b is stale now (t=500, fresh_until=200) but NOT past hard expiry (3000)
    assert {:ok, 2, :stale} = SwrCache.get(c, :b)
  end

  # -------------------------------------------------------
  # Validation
  # -------------------------------------------------------

  test "put rejects non-positive windows", %{c: c} do
    assert_raise FunctionClauseError, fn ->
      SwrCache.put(c, :a, 1, 0, 100, fn -> :_ end)
    end

    assert_raise FunctionClauseError, fn ->
      SwrCache.put(c, :a, 1, 100, 0, fn -> :_ end)
    end
  end

  test "re-put overwrites the loader used for revalidation", %{c: c} do
    parent = self()

    loader_a = fn ->
      send(parent, :loader_a)
      :va
    end

    loader_b = fn ->
      send(parent, :loader_b)
      :vb
    end

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, loader_a)
    # Overwrite the same key — the new loader must replace the old one.
    :ok = SwrCache.put(c, :a, :v2, 1_000, 2_000, loader_b)

    Clock.advance(1_000)
    assert {:ok, :v2, :stale} = SwrCache.get(c, :a)

    assert_receive :loader_b, 500
    refute_receive :loader_a, 50
  end

  test "sweep keeps a stale entry whose revalidation failed", %{c: c} do
    Clock.set(0)
    parent = self()

    loader = fn ->
      send(parent, :loader_ran)
      raise "boom"
    end

    # fresh until 100, hard expiry at 2100.
    :ok = SwrCache.put(c, :a, :v1, 100, 2_000, loader)

    Clock.advance(150)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
    assert_receive :loader_ran, 500
    :ok = wait_for_idle(c)

    # Still inside the stale window (t=150 < 2100): sweep must NOT drop it.
    send(c, :sweep)
    assert %{entries: 1} = SwrCache.stats(c)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
  end

  test "delete on a missing key returns :ok", %{c: c} do
    assert :ok = SwrCache.delete(c, :never_existed)
    assert :miss = SwrCache.get(c, :never_existed)
  end
end
```
