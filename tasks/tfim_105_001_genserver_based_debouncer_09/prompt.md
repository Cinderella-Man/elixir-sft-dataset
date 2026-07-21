# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Debouncer do
  @moduledoc """
  A `GenServer` that debounces zero-arity function calls on a per-key basis.

  Rapid calls sharing the same key are coalesced: each new call for a key
  resets that key's timer and replaces the pending function, so only the most
  recently supplied function runs once the burst settles (after `delay_ms`
  elapses with no further calls for that key). Different keys are fully
  independent, each with their own timer and schedule.

  ## Example

      {:ok, _pid} = Debouncer.start_link([])

      # Only the last func runs, ~50ms after the final call.
      Debouncer.call(:save, 50, fn -> IO.puts("v1") end)
      Debouncer.call(:save, 50, fn -> IO.puts("v2") end)
      Debouncer.call(:save, 50, fn -> IO.puts("v3") end)
      #=> eventually prints "v3"
  """

  use GenServer

  @doc """
  Starts the debouncer process.

  Accepts a `:name` option for process registration, defaulting to `Debouncer`
  (the module name) when not provided.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Schedules `func` (a zero-arity function) to run after `delay_ms` milliseconds
  on the given `key`.

  If another `call/3` for the same `key` arrives before the pending timer fires,
  the timer is reset and `func` replaces the previously pending function, so only
  the most recent `func` for a burst runs (exactly once).

  Returns `:ok` promptly without blocking on `func`. Targets the process
  registered under the name `Debouncer`.
  """
  @spec call(term(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:debounce, key, delay_ms, func}, state) do
    # Cancel any pending timer for this key so the burst is coalesced. If the
    # old timer already fired, its message may be sitting in our queue —
    # cancellation cannot recall it, which is why every arm carries a unique
    # ref: handle_info/2 recognizes and drops the stale message.
    case Map.get(state, key) do
      {_ref, timer, _old_func} -> Process.cancel_timer(timer)
      nil -> :ok
    end

    ref = make_ref()
    timer = Process.send_after(self(), {:fire, key, ref}, delay_ms)
    {:noreply, Map.put(state, key, {ref, timer, func})}
  end

  @impl true
  def handle_info({:fire, key, ref}, state) do
    case Map.get(state, key) do
      {^ref, _timer, func} ->
        # Run the func off the server's reduction path so a slow or crashing
        # func can't wedge the GenServer.
        spawn(fn -> func.() end)
        {:noreply, Map.delete(state, key)}

      _ ->
        # Stale fire: the key was re-debounced (or already fired) after this
        # timer's message was queued, so its func was replaced. Dropping the
        # message keeps the replacement's delay real.
        {:noreply, state}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DebouncerTest do
  use ExUnit.Case, async: false

  setup do
    # Starts Debouncer.start_link([]) which registers under the default name.
    start_supervised!(Debouncer)
    :ok
  end

  # Build a zero-arity func that notifies the test process when invoked.
  defp notify(tag) do
    test = self()
    fn -> send(test, tag) end
  end

  # -------------------------------------------------------
  # Coalescing: only the last func runs, exactly once
  # -------------------------------------------------------

  test "coalesces rapid calls on the same key — only the last func runs" do
    Debouncer.call("k", 150, notify({:ran, 1}))
    Debouncer.call("k", 150, notify({:ran, 2}))
    Debouncer.call("k", 150, notify({:ran, 3}))

    # Only the most recently supplied func should ever fire.
    assert_receive {:ran, 3}, 600

    # The earlier funcs from the burst must never have run.
    refute_received {:ran, 1}
    refute_received {:ran, 2}

    # And nothing else fires afterwards.
    refute_receive {:ran, _}, 250
  end

  test "executes the surviving func exactly once" do
    Debouncer.call("k", 100, notify(:once))

    assert_receive :once, 400
    refute_receive :once, 300
  end

  # -------------------------------------------------------
  # The delay is respected
  # -------------------------------------------------------

  test "does not execute before the delay elapses" do
    Debouncer.call("k", 200, notify(:done))

    # Well before the 200ms delay, nothing should have fired.
    refute_receive :done, 120

    # But it does fire once the delay has passed.
    assert_receive :done, 400
  end

  test "each call resets the timer" do
    # t=0: schedule v1 (would fire at t=200 if never reset)
    Debouncer.call("k", 200, notify(:v1))

    Process.sleep(100)

    # t=100: reset the timer with v2 (should now fire near t=300)
    Debouncer.call("k", 200, notify(:v2))

    # From t=100..t=250: v1 would have fired at t=200 if the timer
    # had NOT been reset. It must not.
    refute_receive :v1, 150

    # v2 fires after its own full delay.
    assert_receive :v2, 500

    # v1 never runs.
    refute_received :v1
  end

  test "a stale timer message cannot run the replacement func early" do
    # Arm f1, then SUSPEND the server so we control the message order: the
    # re-debounce cast is queued first, and the old timer's fire message lands
    # behind it while the server is suspended. On resume the server processes
    # the re-debounce, then the old timer's message — which must be recognized
    # as stale and dropped, not run the freshly armed func ~150ms early.
    Debouncer.call("k", 80, notify(:old_func))
    pid = Process.whereis(Debouncer)
    :sys.suspend(pid)
    Debouncer.call("k", 300, notify(:new_func))
    Process.sleep(150)
    :sys.resume(pid)

    # The replacement waits out its own full delay...
    refute_receive :new_func, 200
    # ...then fires exactly once.
    assert_receive :new_func, 500
    # The func it replaced never runs.
    refute_received :old_func
  end

  # -------------------------------------------------------
  # Keys are independent
  # -------------------------------------------------------

  test "different keys are independent" do
    Debouncer.call("a", 100, notify({:key, "a"}))
    Debouncer.call("b", 100, notify({:key, "b"}))

    assert_receive {:key, "a"}, 400
    assert_receive {:key, "b"}, 400
  end

  test "coalescing one key leaves other keys untouched" do
    # Burst on "a" — only the last should survive.
    Debouncer.call("a", 150, notify({:a, 1}))
    Debouncer.call("a", 150, notify({:a, 2}))

    # A single, independent call on "b".
    Debouncer.call("b", 150, notify(:b_ran))

    assert_receive {:a, 2}, 500
    assert_receive :b_ran, 500

    refute_received {:a, 1}
  end

  # -------------------------------------------------------
  # A fresh call after firing triggers a second execution
  # -------------------------------------------------------

  test "a call after the previous one fired triggers a fresh execution" do
    # TODO
  end

  # -------------------------------------------------------
  # Return value + non-blocking contract
  # -------------------------------------------------------

  test "call/3 returns :ok" do
    assert :ok = Debouncer.call("k", 100, notify(:x))
    assert_receive :x, 400
  end

  test "call/3 returns promptly even when the eventual func would block" do
    slow = fn ->
      Process.sleep(300)
      send(self(), :never_matters)
    end

    # Scheduling must not block on the func's future runtime.
    {micros, :ok} = :timer.tc(fn -> Debouncer.call("slow", 50, slow) end)
    assert micros < 100_000
  end

  # -------------------------------------------------------
  # Arbitrary key terms
  # -------------------------------------------------------

  test "keys can be arbitrary terms" do
    Debouncer.call({:user, 1}, 100, notify(:tuple_key))
    Debouncer.call(:atom_key, 100, notify(:atom_key_ran))

    assert_receive :tuple_key, 400
    assert_receive :atom_key_ran, 400
  end

  # -------------------------------------------------------
  # delay_ms = 0 is legal, and the func is never run inline
  # -------------------------------------------------------

  test "delay_ms of 0 is accepted and runs the func asynchronously, not in the caller" do
    test = self()

    # 0 is a legal, non-negative delay: "fire on the next scheduler pass".
    assert :ok = Debouncer.call("zero", 0, fn -> send(test, {:zero_ran, self()}) end)

    assert_receive {:zero_ran, runner}, 400

    # The func must never run inline in the calling process.
    refute runner == test
  end

  # -------------------------------------------------------
  # Argument validation (exception TYPE only)
  # -------------------------------------------------------

  test "call/3 raises FunctionClauseError for a bad delay or a non-zero-arity func" do
    # Negative delay: below the non-negative-integer contract.
    assert_raise FunctionClauseError, fn -> Debouncer.call("k", -1, fn -> :noop end) end

    # Non-integer delay.
    assert_raise FunctionClauseError, fn -> Debouncer.call("k", 100.0, fn -> :noop end) end

    # Func of the wrong arity.
    assert_raise FunctionClauseError, fn -> Debouncer.call("k", 100, fn _x -> :noop end) end

    # None of the rejected calls may have been sent to the server: a valid call
    # on the same key still starts a brand-new debounce cycle and fires once.
    Debouncer.call("k", 50, notify(:valid))
    assert_receive :valid, 400
    refute_receive :valid, 200
  end

  # -------------------------------------------------------
  # Independent schedules: a later, shorter delay fires first
  # -------------------------------------------------------

  test "a short-delay key fires before a long-delay key that was scheduled earlier" do
    Debouncer.call("long", 250, notify(:long))
    Debouncer.call("short", 50, notify(:short))

    # The short key fires on its own schedule, well before the long one...
    assert_receive :short, 200
    refute_received :long

    # ...and the pending long key is unaffected, firing after its own delay.
    assert_receive :long, 500
  end

  test "start_link/1 registers under the module name by default and rejects a duplicate" do
    default = Process.whereis(Debouncer)
    assert is_pid(default)

    # The setup instance was started with no :name, so it must own the default
    # registration; a second start under the same name is rejected.
    assert {:error, {:already_started, ^default}} = Debouncer.start_link([])
  end

  test "a raising func leaves the server alive and later calls still honored" do
    server = Process.whereis(Debouncer)
    test = self()

    Debouncer.call("boom", 20, fn ->
      send(test, :boom_ran)
      raise "boom"
    end)

    assert_receive :boom_ran, 400

    Debouncer.call("after_boom", 20, notify(:after_ran))
    assert_receive :after_ran, 400

    assert Process.alive?(server)
    assert Process.whereis(Debouncer) == server
  end

  test "a replacement call with a shorter delay fires on the new shorter delay" do
    Debouncer.call(:shrink, 500, notify(:slow_v1))
    Debouncer.call(:shrink, 20, notify(:fast_v2))

    # The delay in force is the newest call's 20ms, not the earlier 500ms.
    assert_receive :fast_v2, 250
    refute_received :slow_v1

    # And the replaced func never runs, not even at the old 500ms deadline.
    refute_receive :slow_v1, 700
  end

  test "a still-running slow func does not hold back another key's func" do
    test = self()

    Debouncer.call(:slow_a, 20, fn ->
      send(test, {:a_started, self()})

      receive do
        :release -> send(test, :a_done)
      after
        2_000 -> :a_timeout
      end
    end)

    Debouncer.call(:quick_b, 40, notify(:b_ran))

    assert_receive {:a_started, runner}, 400
    # :a is still parked inside its receive here — :b must fire anyway.
    assert_receive :b_ran, 400

    send(runner, :release)
    assert_receive :a_done, 400
  end

  test "atom, binary and tuple keys of the same shape debounce independently" do
    Debouncer.call(:a, 30, notify(:atom_key_a))
    Debouncer.call("a", 30, notify(:string_key_a))
    Debouncer.call({:a, 1}, 30, notify(:tuple_key_a))

    # No key coalesces any other: all three funcs survive and run.
    assert_receive :atom_key_a, 400
    assert_receive :string_key_a, 400
    assert_receive :tuple_key_a, 400
  end

  test "call/3 returns promptly even while the server is not processing messages" do
    pid = Process.whereis(Debouncer)

    # With the server unable to process anything, a blocking request would hang.
    :sys.suspend(pid)
    {micros, result} = :timer.tc(fn -> Debouncer.call("busy", 20, notify(:busy_ran)) end)
    :sys.resume(pid)

    assert result == :ok
    assert micros < 100_000

    # The fire-and-forget request is still honored once the server runs again.
    assert_receive :busy_ran, 400
  end

  # -------------------------------------------------------
  # The :name start option
  # -------------------------------------------------------

  # A registration name that cannot collide with any other test's instance.
  defp unique_name(prefix) do
    :"#{prefix}_#{System.pid()}_#{System.unique_integer([:positive])}"
  end

  test "start_link/1 registers a second instance under a custom :name" do
    default = Process.whereis(Debouncer)
    name = unique_name("debouncer_alt")

    # The :name option decides the registration, so this instance coexists with
    # the default one instead of colliding with it.
    assert {:ok, alt} = Debouncer.start_link(name: name)
    assert alt != default
    assert Process.whereis(name) == alt

    # A duplicate start under that same custom name is what gets rejected.
    assert {:error, {:already_started, ^alt}} = Debouncer.start_link(name: name)

    # The default registration is untouched by the custom-named instance.
    assert Process.whereis(Debouncer) == default

    GenServer.stop(alt)
  end

  test "call/3 targets the default process regardless of another instance's :name" do
    default = Process.whereis(Debouncer)
    name = unique_name("debouncer_other")
    {:ok, other} = Debouncer.start_link(name: name)

    # Scheduling still works while a differently-named instance is running.
    Debouncer.call(:routed, 20, notify(:ran_while_other_up))
    assert_receive :ran_while_other_up, 400

    # Work was never routed to the custom-named instance: stopping it leaves
    # the default process serving calls exactly as before.
    GenServer.stop(other)
    refute Process.alive?(other)

    Debouncer.call(:routed, 20, notify(:ran_after_other_down))
    assert_receive :ran_after_other_down, 400
    assert Process.whereis(Debouncer) == default
  end
end
```
