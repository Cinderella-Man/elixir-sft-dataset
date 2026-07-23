# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule MaxWaitDebouncer do
  @moduledoc """
  A `GenServer` debouncer with a maximum-wait guarantee and manual flush/cancel.

  Like a normal debouncer it coalesces rapid same-key calls (resetting the timer
  and replacing the pending func), but it also guarantees the pending func fires
  no later than `max_ms` after the burst's first call — so a sustained burst
  can't starve execution forever. `flush/1` runs the pending func immediately;
  `cancel/1` drops it.
  """

  use GenServer

  @doc """
  Starts the debouncer. Accepts a `:name` option, defaulting to `MaxWaitDebouncer`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Schedules `func` for `key`, coalescing with `delay_ms` but guaranteeing a fire
  within `max_ms` of the burst's first call. Returns `:ok` promptly.
  """
  @spec call(term(), non_neg_integer(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, max_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_integer(max_ms) and
             max_ms >= delay_ms and
             is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, max_ms, func})
  end

  @doc "Immediately runs the pending func for `key` (if any) and clears state."
  @spec flush(term()) :: :ok
  def flush(key), do: GenServer.call(__MODULE__, {:flush, key})

  @doc "Discards the pending func for `key` without running it."
  @spec cancel(term()) :: :ok
  def cancel(key), do: GenServer.call(__MODULE__, {:cancel, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, max_ms, func}, state) do
    now = mono_ms()

    first_at =
      case Map.get(state, key) do
        %{timer: ref, first_at: at} ->
          Process.cancel_timer(ref)
          at

        nil ->
          now
      end

    remaining_until_max = max(0, first_at + max_ms - now)
    fire_in = max(0, min(delay_ms, remaining_until_max))
    ref = Process.send_after(self(), {:fire, key}, fire_in)

    entry = %{timer: ref, func: func, first_at: first_at}
    {:noreply, Map.put(state, key, entry)}
  end

  @impl true
  def handle_call({:flush, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref, func: func}, new_state} ->
        Process.cancel_timer(ref)
        run(func)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:cancel, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref}, new_state} ->
        Process.cancel_timer(ref)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {%{func: func}, new_state} ->
        run(func)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end

  defp run(func), do: spawn(fn -> func.() end)

  defp mono_ms, do: System.monotonic_time(:millisecond)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule MaxWaitDebouncerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(MaxWaitDebouncer)
    :ok
  end

  defp notify(tag) do
    test = self()
    fn -> send(test, tag) end
  end

  # -------------------------------------------------------
  # Basic coalescing + delay
  # -------------------------------------------------------

  test "coalesces to the last func after the delay when the burst settles" do
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 1}))
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 2}))
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 3}))

    assert_receive {:ran, 3}, 600
    refute_received {:ran, 1}
    refute_received {:ran, 2}
  end

  test "does not run before the delay elapses" do
    MaxWaitDebouncer.call("k", 200, 1000, notify(:done))
    refute_receive :done, 120
    assert_receive :done, 400
  end

  # -------------------------------------------------------
  # Max-wait guarantee
  # -------------------------------------------------------

  test "fires by max_ms even though the delay timer keeps resetting" do
    # delay=150, max=250. A plain debouncer would keep pushing the fire to
    # ~last_call + 150; the max-wait bound forces a fire at ~first_call + 250.
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))
    Process.sleep(100)
    # t=100: resets delay timer (would fire at ~250 anyway)
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))
    Process.sleep(100)
    # t=200: delay would push fire to ~350, but max deadline is ~250.
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))

    # From here (~t=200) the max deadline (~250) is only ~50ms away, well before
    # the ~350 the delay timer would give.
    assert_receive :fired, 175
  end

  test "single call within max simply obeys the normal delay" do
    MaxWaitDebouncer.call("k", 100, 1000, notify(:one))
    assert_receive :one, 400
    refute_receive :one, 200
  end

  # -------------------------------------------------------
  # flush / cancel
  # -------------------------------------------------------

  test "flush runs the pending func immediately" do
    MaxWaitDebouncer.call("k", 500, 5000, notify(:flushed))
    assert :ok = MaxWaitDebouncer.flush("k")

    # Runs well before the 500ms delay would have.
    assert_receive :flushed, 200
    # And does not run a second time.
    refute_receive :flushed, 600
  end

  test "flush with nothing pending is a no-op returning :ok" do
    assert :ok = MaxWaitDebouncer.flush("absent")
    refute_receive _, 100
  end

  test "cancel discards the pending func" do
    MaxWaitDebouncer.call("k", 200, 1000, notify(:cancelled))
    assert :ok = MaxWaitDebouncer.cancel("k")

    refute_receive :cancelled, 400
  end

  # -------------------------------------------------------
  # Independence + fresh bursts + contract
  # -------------------------------------------------------

  test "different keys are independent" do
    MaxWaitDebouncer.call("a", 100, 1000, notify({:key, "a"}))
    MaxWaitDebouncer.call("b", 100, 1000, notify({:key, "b"}))

    assert_receive {:key, "a"}, 400
    assert_receive {:key, "b"}, 400
  end

  test "a fresh call after firing starts a new max-wait window" do
    MaxWaitDebouncer.call("k", 100, 1000, notify(:first))
    assert_receive :first, 400

    MaxWaitDebouncer.call("k", 100, 1000, notify(:second))
    assert_receive :second, 400
  end

  test "call/4 returns :ok promptly even with a blocking func" do
    slow = fn -> Process.sleep(300) end
    {micros, :ok} = :timer.tc(fn -> MaxWaitDebouncer.call("s", 50, 500, slow) end)
    assert micros < 100_000
  end

  test "accepts max_ms equal to delay_ms and fires once" do
    # The contract is `max_ms >= delay_ms`, so equality must be accepted.
    assert :ok = MaxWaitDebouncer.call("k", 100, 100, notify(:equal))

    assert_receive :equal, 400
    refute_receive :equal, 200
  end

  test "accepts a zero delay and fires promptly" do
    # TODO
  end

  # -------------------------------------------------------
  # Max-wait deadline is anchored to the burst's first call
  # -------------------------------------------------------

  test "the max-wait fire lands near first_call + max_ms, not last_call + delay" do
    # delay=200, max=250. Calls land at roughly t=0, t=80, t=165, each one
    # resetting the delay timer. A debouncer that only honours delay_ms would
    # fire at ~165 + 200 = ~365; the max-wait bound pins the fire at ~250,
    # i.e. within ~85ms of the final call. The window below expires at ~305,
    # so only an implementation that respects max_ms can satisfy it.
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))
    refute_receive :fired, 80
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))
    refute_receive :fired, 80
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))

    assert_receive :fired, 140
  end

  # -------------------------------------------------------
  # start_link/1 registration
  # -------------------------------------------------------

  test "start_link/1 registers the process under a custom :name" do
    # The default name is already covered by the suite's setup; here the
    # :name option must actually drive registration.
    name = :"max_wait_debouncer_#{System.pid()}_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = MaxWaitDebouncer.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.alive?(pid)
    assert Process.whereis(name) == pid
  end

  test "a second call restarts the delay window instead of firing at the first call's deadline" do
    # delay=200, max=5000 (max can never bind here). The second call lands at
    # ~t=150, so an implementation that resets the timer fires at ~350. One that
    # kept the original deadline would fire at ~200, inside the refute window.
    MaxWaitDebouncer.call("k", 200, 5000, notify(:reset))
    refute_receive :reset, 150
    MaxWaitDebouncer.call("k", 200, 5000, notify(:reset))
    refute_receive :reset, 150

    assert_receive :reset, 300
  end

  test "a max-wait fire runs the newest func, not the one that opened the burst" do
    # delay=150, max=200. Second call at ~t=100 leaves 100ms of max window, so
    # fire_in = min(150, 100) = 100 and the fire at ~t=200 is the max-wait one.
    MaxWaitDebouncer.call("k", 150, 200, notify({:ran, 1}))
    refute_receive {:ran, _}, 100
    MaxWaitDebouncer.call("k", 150, 200, notify({:ran, 2}))

    assert_receive {:ran, 2}, 250
    refute_received {:ran, 1}
  end

  test "after a max-wait fire the next call gets a full fresh window, not the expired one" do
    # Force a max-wait fire at ~t=200 (delay=150, max=200, second call at ~100).
    MaxWaitDebouncer.call("k", 150, 200, notify(:burst_one))
    refute_receive :burst_one, 100
    MaxWaitDebouncer.call("k", 150, 200, notify(:burst_one))
    assert_receive :burst_one, 250

    # Fresh burst: delay=300, max=300 must fire ~300ms from now. If the old
    # first_call_at survived the fire, remaining_until_max would already be
    # ~0-100ms and this would fire almost immediately, inside the refute window.
    MaxWaitDebouncer.call("k", 300, 300, notify(:burst_two))
    refute_receive :burst_two, 200
    assert_receive :burst_two, 350
  end

  test "a key's burst-start time does not leak into another key's max-wait window" do
    MaxWaitDebouncer.call("a", 150, 200, notify({:k, :a}))
    refute_receive {:k, :a}, 120

    # "b" opens its own burst at ~t=120, so its max deadline is ~t=420. If it
    # shared "a"'s burst start (~t=0) the remaining window would be ~180ms and
    # "b" would fire at ~t=300, inside the refute window below.
    MaxWaitDebouncer.call("b", 300, 300, notify({:k, :b}))

    assert_receive {:k, :a}, 200
    refute_receive {:k, :b}, 200
    assert_receive {:k, :b}, 250
  end

  test "a call after flush starts a fresh burst with an untouched max-wait window" do
    # Both durations respect the `max_ms >= delay_ms` contract; the flush below
    # runs the pending func long before either bound would fire it.
    MaxWaitDebouncer.call("k", 500, 500, notify(:pending))
    assert :ok = MaxWaitDebouncer.flush("k")
    assert_receive :pending, 200

    # If flush left the burst start behind, the ~300ms max window would already
    # be spent and this call would fire near-immediately instead of at ~+250.
    MaxWaitDebouncer.call("k", 250, 300, notify(:refreshed))
    refute_receive :refreshed, 150
    assert_receive :refreshed, 300
  end

  test "call/4 rejects a max_ms smaller than delay_ms" do
    assert_raise FunctionClauseError, fn ->
      MaxWaitDebouncer.call("k", 200, 100, notify(:never))
    end

    refute_receive :never, 400
  end

  # -------------------------------------------------------
  # A firing func runs off the server's reduction path
  # -------------------------------------------------------

  test "a running slow func does not wedge the server for other keys" do
    test = self()
    # Announces that it has begun, then stays busy far longer than any of the
    # bounds asserted below, so the server is observed while the func runs.
    slow = fn ->
      send(test, :slow_started)
      Process.sleep(1_000)
    end

    MaxWaitDebouncer.call("slow", 0, 0, slow)
    assert_receive :slow_started, 500

    # The func is still running here: a synchronous call must still be answered
    # promptly, and a fresh key must still get its own fire.
    {micros, :ok} = :timer.tc(fn -> MaxWaitDebouncer.cancel("absent") end)
    assert micros < 300_000

    MaxWaitDebouncer.call("other", 0, 0, notify(:other_ran))
    assert_receive :other_ran, 400
  end

  test "a crashing func neither kills the server nor loses other pending work" do
    server = Process.whereis(MaxWaitDebouncer)

    # Pending work on an untouched key; it must survive the crash below.
    MaxWaitDebouncer.call("survivor", 250, 250, notify(:survived))

    test = self()

    boom = fn ->
      send(test, :boom_started)
      raise "boom"
    end

    MaxWaitDebouncer.call("boom", 0, 0, boom)
    assert_receive :boom_started, 500

    assert_receive :survived, 800
    assert :ok = MaxWaitDebouncer.flush("absent")
    assert Process.whereis(MaxWaitDebouncer) == server
  end
end
```
