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
  def call(key, delay_ms, func) when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:debounce, key, delay_ms, func}, state) do
    # Cancel any pending timer for this key so the burst is coalesced.
    case Map.get(state, key) do
      {timer_ref, _old_func} -> Process.cancel_timer(timer_ref)
      nil -> :ok
    end

    timer_ref = Process.send_after(self(), {:fire, key}, delay_ms)
    {:noreply, Map.put(state, key, {timer_ref, func})}
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {{_timer_ref, func}, new_state} ->
        # Run the func off the server's reduction path so a slow or crashing
        # func can't wedge the GenServer.
        spawn(fn -> func.() end)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
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
    # TODO
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
    Debouncer.call("k", 100, notify(:first))
    assert_receive :first, 400

    Debouncer.call("k", 100, notify(:second))
    assert_receive :second, 400
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
end
```
