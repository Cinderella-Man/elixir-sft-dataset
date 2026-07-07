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
