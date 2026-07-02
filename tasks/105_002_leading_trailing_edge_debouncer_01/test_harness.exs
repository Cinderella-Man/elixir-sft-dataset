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
end