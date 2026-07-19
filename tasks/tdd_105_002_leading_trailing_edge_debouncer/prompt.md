# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule EdgeDebouncerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(EdgeDebouncer)
    :ok
  end

  defp notify(tag) do
    test = self()
    fn -> send(test, tag) end
  end

  # -------------------------------------------------------
  # Trailing edge (default)
  # -------------------------------------------------------

  test "trailing edge coalesces to the last func after the delay" do
    EdgeDebouncer.call("k", 150, notify({:ran, 1}))
    EdgeDebouncer.call("k", 150, notify({:ran, 2}))
    EdgeDebouncer.call("k", 150, notify({:ran, 3}), edge: :trailing)

    assert_receive {:ran, 3}, 600
    refute_received {:ran, 1}
    refute_received {:ran, 2}
    refute_receive {:ran, _}, 250
  end

  test "trailing edge does not run before the delay elapses" do
    EdgeDebouncer.call("k", 200, notify(:done))
    refute_receive :done, 120
    assert_receive :done, 400
  end

  # -------------------------------------------------------
  # Leading edge
  # -------------------------------------------------------

  test "leading edge runs the first func immediately and nothing else" do
    EdgeDebouncer.call("k", 200, notify({:ran, 1}), edge: :leading)
    EdgeDebouncer.call("k", 200, notify({:ran, 2}), edge: :leading)
    EdgeDebouncer.call("k", 200, notify({:ran, 3}), edge: :leading)

    # First func fires right away.
    assert_receive {:ran, 1}, 100
    # No later func ever runs, and no trailing execution occurs.
    refute_receive {:ran, 2}, 400
    refute_received {:ran, 3}
  end

  # -------------------------------------------------------
  # Both edges
  # -------------------------------------------------------

  test "both edges fire leading immediately and trailing at the end" do
    EdgeDebouncer.call("k", 150, notify({:ran, 1}), edge: :both)
    EdgeDebouncer.call("k", 150, notify({:ran, 2}), edge: :both)
    EdgeDebouncer.call("k", 150, notify({:ran, 3}), edge: :both)

    # Leading is the first func.
    assert_receive {:ran, 1}, 100
    # Trailing is the most recent func.
    assert_receive {:ran, 3}, 600
    # The middle func never runs.
    refute_received {:ran, 2}
  end

  test "both edges with a single call fires leading only (never twice)" do
    EdgeDebouncer.call("k", 150, notify(:solo), edge: :both)

    assert_receive :solo, 100
    # No trailing execution for a lone call.
    refute_receive :solo, 400
  end

  # -------------------------------------------------------
  # Independence + fresh bursts
  # -------------------------------------------------------

  test "different keys are independent" do
    EdgeDebouncer.call("a", 100, notify({:key, "a"}), edge: :leading)
    EdgeDebouncer.call("b", 100, notify({:key, "b"}))

    assert_receive {:key, "a"}, 100
    assert_receive {:key, "b"}, 400
  end

  test "a fresh burst after settling fires leading again" do
    EdgeDebouncer.call("k", 100, notify(:first), edge: :leading)
    assert_receive :first, 100

    # Let the burst settle.
    Process.sleep(200)

    EdgeDebouncer.call("k", 100, notify(:second), edge: :leading)
    assert_receive :second, 100
  end

  # -------------------------------------------------------
  # Contract
  # -------------------------------------------------------

  test "call/4 returns :ok and does not block on the func" do
    slow = fn ->
      Process.sleep(300)
      :ok
    end

    {micros, :ok} = :timer.tc(fn -> EdgeDebouncer.call("s", 50, slow) end)
    assert micros < 100_000
  end

  test "invalid edge raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      EdgeDebouncer.call("k", 100, notify(:x), edge: :bogus)
    end
  end

  # -------------------------------------------------------
  # Funcs run off the server's reduction path
  # -------------------------------------------------------

  test "a leading func that never returns does not wedge the server" do
    test = self()

    # Blocks forever until explicitly released, without sleeping the test.
    blocking = fn ->
      send(test, {:blocking_started, self()})

      receive do
        :release -> :ok
      end
    end

    EdgeDebouncer.call("blocked", 100, blocking, edge: :leading)
    assert_receive {:blocking_started, blocker}, 500

    # While that func is still running, the server keeps handling other keys:
    # a leading call fires immediately and a trailing call still settles.
    EdgeDebouncer.call("other", 100, notify(:other_leading), edge: :leading)
    assert_receive :other_leading, 500

    EdgeDebouncer.call("later", 80, notify(:other_trailing))
    assert_receive :other_trailing, 600

    send(blocker, :release)
  end

  @tag :capture_log
  test "a raising func does not crash the server" do
    server = Process.whereis(EdgeDebouncer)

    EdgeDebouncer.call("boom_lead", 50, fn -> raise "boom" end, edge: :leading)
    EdgeDebouncer.call("boom_trail", 50, fn -> raise "boom" end)

    # This trailing execution lands after the raising trailing func has fired.
    EdgeDebouncer.call("ok", 100, notify(:settled))
    assert_receive :settled, 600

    # The same process is still registered and still debouncing new bursts.
    assert Process.whereis(EdgeDebouncer) == server

    EdgeDebouncer.call("alive", 50, notify(:alive), edge: :leading)
    assert_receive :alive, 300
  end

  test "a second call restarts the delay so trailing survives the original deadline" do
    # t0: arm a 200ms trailing burst for "k".
    EdgeDebouncer.call("k", 200, notify(:late))

    # A separate key acts as a deterministic ~120ms clock (keys are independent).
    EdgeDebouncer.call("clock", 120, notify(:tick))
    assert_receive :tick, 500

    # ~t0+120: re-call "k" — the deadline must restart from now (~t0+320),
    # not stay at the original ~t0+200.
    EdgeDebouncer.call("k", 200, notify(:late))
    refute_receive :late, 120

    assert_receive :late, 500
  end

  test "the opening call's edge wins over a later call's edge option" do
    EdgeDebouncer.call("k", 150, notify(:lead), edge: :leading)
    EdgeDebouncer.call("k", 150, notify(:tail), edge: :trailing)

    # The burst was opened as :leading, so the first func fires immediately...
    assert_receive :lead, 200
    # ...and no trailing execution occurs even though a later call said :trailing.
    refute_receive :tail, 500
  end

  test "a settled :both burst leaves no state and the next call fires leading again" do
    EdgeDebouncer.call("k", 100, notify({:b, 1}), edge: :both)
    EdgeDebouncer.call("k", 100, notify({:b, 2}), edge: :both)

    assert_receive {:b, 1}, 200
    # Trailing arriving means the burst has settled and the key is cleared.
    assert_receive {:b, 2}, 500

    EdgeDebouncer.call("k", 100, notify({:b, 3}), edge: :both)
    assert_receive {:b, 3}, 200
  end

  test "the :both trailing func runs exactly once when the burst settles" do
    EdgeDebouncer.call("k", 100, notify(:x), edge: :both)
    EdgeDebouncer.call("k", 100, notify(:x), edge: :both)

    # Leading, then exactly one trailing — never a third execution.
    assert_receive :x, 200
    assert_receive :x, 500
    refute_receive :x, 300
  end

  test "start_link/1 registers under a custom :name and returns {:ok, pid}" do
    assert {:ok, pid} = EdgeDebouncer.start_link(name: :edge_debouncer_alt)

    assert Process.whereis(:edge_debouncer_alt) == pid
    # The default-named process from setup/1 is a distinct registration.
    assert Process.whereis(EdgeDebouncer) != pid
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
