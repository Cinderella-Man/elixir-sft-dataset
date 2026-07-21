# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key), do: GenServer.call(server, {:get, key})

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

## Test harness — implement the `# TODO` test

```elixir
defmodule RefreshAheadCacheTest do
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

  # A programmable loader backed by an Agent — lets tests control what the
  # loader returns and count its invocations.
  defmodule Loader do
    use Agent

    def start_link(values) do
      Agent.start_link(fn -> %{values: values, calls: 0} end, name: __MODULE__)
    end

    # Returns the next queued value, incrementing the call count.
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

    # A slow loader: sleeps, then calls `next_value/0`.  Used to create
    # observable "refresh in flight" windows.
    def slow_next_value(sleep_ms) do
      Process.sleep(sleep_ms)
      next_value()
    end

    def calls, do: Agent.get(__MODULE__, & &1.calls)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      RefreshAheadCache.start_link(
        clock: &Clock.now/0,
        sweep_interval_ms: :infinity,
        refresh_threshold: 0.8
      )

    %{c: pid}
  end

  # Wait for any in-flight refreshes to settle.  We poll stats instead of
  # sleeping a fixed duration to keep tests robust.
  defp wait_for_idle(c, timeout_ms \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fn ->
      case RefreshAheadCache.stats(c) do
        %{refreshes_in_flight: 0} -> :idle
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

  # Poll a public-API predicate until it holds or the deadline passes.  Returns
  # :ok as soon as it holds, :timeout otherwise — never waits a fixed duration
  # for the observed effect itself.
  defp poll_until(fun, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fun)
    |> Enum.reduce_while(:timeout, fn
      true, _ ->
        {:halt, :ok}

      false, acc ->
        if System.monotonic_time(:millisecond) > deadline do
          {:halt, acc}
        else
          Process.sleep(5)
          {:cont, acc}
        end
    end)
  end

  # -------------------------------------------------------
  # Basic put/get/delete (TTLCache parity)
  # -------------------------------------------------------

  test "put/get round-trip", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :should_not_be_called end)
    assert {:ok, 1} = RefreshAheadCache.get(c, :a)
  end

  test "missing key returns :miss", %{c: c} do
    assert :miss = RefreshAheadCache.get(c, :nope)
  end

  test "hard expiry returns :miss and evicts", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :never end)

    Clock.advance(1_000)
    assert :miss = RefreshAheadCache.get(c, :a)

    assert %{entries: 0} = RefreshAheadCache.stats(c)
  end

  test "delete removes entry", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :never end)
    :ok = RefreshAheadCache.delete(c, :a)
    assert :miss = RefreshAheadCache.get(c, :a)
  end

  # -------------------------------------------------------
  # No refresh below threshold
  # -------------------------------------------------------

  test "get below refresh threshold does NOT trigger loader", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    # threshold 0.8 of 1000ms = 800ms.  At 500ms we are still "fresh."
    Clock.advance(500)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 0
  end

  # -------------------------------------------------------
  # Refresh triggered at threshold (the defining property)
  # -------------------------------------------------------

  test "get past refresh threshold triggers loader; subsequent gets see new value", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    # Past threshold (0.8 * 1000 = 800ms).
    Clock.advance(850)

    # This get returns the OLD value and schedules a refresh.
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1

    # Next get should see the refreshed value.
    assert {:ok, :v2} = RefreshAheadCache.get(c, :a)
  end

  test "refresh resets TTL to now + original ttl_ms", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    Clock.advance(850)
    RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)

    # The refresh applied at t=850 should set expires_at = 850 + 1000 = 1850.
    # At t=1600 (age=750 < threshold 800) we're still fresh and no new refresh fires.
    Clock.advance(750)
    assert {:ok, :v2} = RefreshAheadCache.get(c, :a)

    # At t=1900 we're past the NEW expiry.
    Clock.advance(300)
    assert :miss = RefreshAheadCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Only one refresh in flight per key
  # -------------------------------------------------------

  test "rapid gets past threshold only trigger ONE refresh", %{c: c} do
    start_supervised!({Loader, [:v2]})

    # Use a slow loader to ensure the first refresh is still in flight while
    # we fire the follow-up gets.
    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)

    # 10 rapid reads
    for _ <- 1..10, do: assert({:ok, :v1} = RefreshAheadCache.get(c, :a))

    # Should see exactly 1 refresh in flight
    %{refreshes_in_flight: n} = RefreshAheadCache.stats(c)
    assert n == 1

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1
  end

  # -------------------------------------------------------
  # Delete cancels the effect of an in-flight refresh
  # -------------------------------------------------------

  test "delete during in-flight refresh discards the refresh result", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)

    # Trigger refresh
    RefreshAheadCache.get(c, :a)
    %{refreshes_in_flight: 1} = RefreshAheadCache.stats(c)

    # Delete while refresh is in flight
    RefreshAheadCache.delete(c, :a)

    # Wait for the refresh to complete — it should have been discarded
    :ok = wait_for_idle(c)
    assert :miss = RefreshAheadCache.get(c, :a)
    assert %{entries: 0} = RefreshAheadCache.stats(c)
  end

  # -------------------------------------------------------
  # Put during in-flight refresh invalidates the refresh
  # -------------------------------------------------------

  test "put during in-flight refresh: the refresh result must not clobber", %{c: c} do
    start_supervised!({Loader, [:from_loader]})

    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)
    # triggers slow refresh
    RefreshAheadCache.get(c, :a)

    # User overwrites manually before refresh completes
    RefreshAheadCache.put(c, :a, :user_set, 1_000, fn -> :ignored end)

    :ok = wait_for_idle(c)

    # The manual put must win
    assert {:ok, :user_set} = RefreshAheadCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Refresh failures leave the existing value intact
  # -------------------------------------------------------

  test "a failing loader leaves the current value in place", %{c: c} do
    :ok =
      RefreshAheadCache.put(c, :a, :good, 1_000, fn -> raise "nope" end)

    Clock.advance(850)
    assert {:ok, :good} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert %{refreshes_in_flight: 0} = RefreshAheadCache.stats(c)

    # Still returns the original value
    assert {:ok, :good} = RefreshAheadCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Hard expiry sweep
  # -------------------------------------------------------

  test "sweep removes hard-expired entries", %{c: c} do
    Clock.set(0)

    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> 99 end)
    :ok = RefreshAheadCache.put(c, :b, 2, 5_000, fn -> 99 end)

    Clock.advance(2_000)
    send(c, :sweep)

    # A synchronous call cannot be served until the sweep message ahead of it
    # in the mailbox has been processed, so the sweep is done once this returns.
    assert %{entries: 1} = RefreshAheadCache.stats(c)

    assert :miss = RefreshAheadCache.get(c, :a)
    assert {:ok, 2} = RefreshAheadCache.get(c, :b)
  end

  # -------------------------------------------------------
  # Option validation
  # -------------------------------------------------------

  test "invalid refresh_threshold raises" do
    assert_raise ArgumentError, fn ->
      RefreshAheadCache.start_link(refresh_threshold: 0.0)
    end

    assert_raise ArgumentError, fn ->
      RefreshAheadCache.start_link(refresh_threshold: 1.5)
    end
  end

  test "refresh triggers exactly at the age >= 800ms boundary", %{c: c} do
    start_supervised!({Loader, [:v2]})
    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    # age 799ms: below the boundary, no refresh must be scheduled.
    Clock.advance(799)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)
    assert Loader.calls() == 0

    # age exactly 800ms: at the boundary the refresh must fire.
    Clock.advance(1)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)
    assert Loader.calls() == 1
  end

  test "sweeping an entry mid-refresh discards the late result, no resurrect", %{c: c} do
    test_pid = self()

    # This loader blocks until released, keeping a refresh in flight
    # deterministically while we sweep the entry out from under it.
    loader = fn ->
      send(test_pid, {:task, self()})

      receive do
        :release -> :ok
      end

      :late_value
    end

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, loader)

    Clock.advance(850)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)
    assert_receive {:task, task_pid}
    assert %{refreshes_in_flight: 1} = RefreshAheadCache.stats(c)

    # Hard-expire the entry, then sweep it while its refresh is still running.
    Clock.advance(200)
    send(c, :sweep)
    assert %{entries: 0} = RefreshAheadCache.stats(c)

    # Release the refresh and wait for its task to fully exit, which guarantees
    # the {:refresh_complete, ...} message is already in the server mailbox.
    ref = Process.monitor(task_pid)
    send(task_pid, :release)
    assert_receive {:DOWN, ^ref, :process, ^task_pid, _}

    # The following synchronous calls drain past that stale message: it must be
    # discarded and must NOT resurrect the swept entry.
    assert :miss = RefreshAheadCache.get(c, :a)
    assert %{entries: 0} = RefreshAheadCache.stats(c)
  end

  test "after a failed refresh a later get retries the refresh", %{c: c} do
    {:ok, cnt} = Agent.start_link(fn -> 0 end)

    loader = fn ->
      n = Agent.get_and_update(cnt, fn n -> {n, n + 1} end)
      if n == 0, do: raise("boom"), else: :recovered
    end

    :ok = RefreshAheadCache.put(c, :a, :orig, 1_000, loader)

    Clock.advance(850)

    # First threshold crossing: schedules a refresh whose loader raises.
    assert {:ok, :orig} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)

    # The failure left the old value in place; this get crosses the threshold
    # again and must start a brand-new (this time succeeding) refresh.
    assert {:ok, :orig} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)

    assert {:ok, :recovered} = RefreshAheadCache.get(c, :a)
  end

  test "re-put overwrites ttl and loader for an existing key", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> :old_refresh end)
    :ok = RefreshAheadCache.put(c, :a, :v2, 2_000, fn -> :new_refresh end)

    # The new ttl (2000) means the entry is still alive at t=1600, where the old
    # ttl (1000) would already be hard-expired.  This get also crosses the new
    # threshold (0.8 * 2000 = 1600), scheduling a refresh via the NEW loader.
    Clock.advance(1_600)
    assert {:ok, :v2} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert {:ok, :new_refresh} = RefreshAheadCache.get(c, :a)
  end

  test "default refresh_threshold triggers at age == 0.8 * ttl", %{c: _c} do
    # TODO
  end

  test "the same loader is reused across successive refreshes", %{c: c} do
    start_supervised!({Loader, [:r1, :r2]})
    :ok = RefreshAheadCache.put(c, :a, :v0, 1_000, &Loader.next_value/0)

    # First refresh at t=850 -> :r1, TTL reset to expires_at = 1850.
    Clock.advance(850)
    assert {:ok, :v0} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)
    assert {:ok, :r1} = RefreshAheadCache.get(c, :a)

    # Second crossing on the refreshed entry must call the loader AGAIN -> :r2.
    Clock.advance(810)
    assert {:ok, :r1} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)
    assert {:ok, :r2} = RefreshAheadCache.get(c, :a)

    assert Loader.calls() == 2
  end

  # -------------------------------------------------------
  # Periodic sweep runs on its own timer
  # -------------------------------------------------------

  test "configured sweep_interval_ms expires entries without any manual sweep" do
    Clock.set(0)

    {:ok, d} =
      RefreshAheadCache.start_link(clock: &Clock.now/0, sweep_interval_ms: 25)

    :ok = RefreshAheadCache.put(d, :a, 1, 1_000, fn -> :never end)
    assert %{entries: 1} = RefreshAheadCache.stats(d)

    # Hard-expire :a on the injected clock.  Nothing here reads :a and nothing
    # triggers a sweep by hand, so only the periodic timer can evict it.
    Clock.advance(1_000)
    assert :ok = poll_until(fn -> RefreshAheadCache.stats(d).entries == 0 end, 2_000)

    # A second entry, expired after the first automatic sweep already ran, must
    # also be evicted — which only happens if the sweep reschedules itself.
    :ok = RefreshAheadCache.put(d, :b, 2, 1_000, fn -> :never end)
    Clock.advance(1_000)
    assert :ok = poll_until(fn -> RefreshAheadCache.stats(d).entries == 0 end, 2_000)
  end
end
```
