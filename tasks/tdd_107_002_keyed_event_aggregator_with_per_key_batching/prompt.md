# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule KeyedAggregatorTest do
  use ExUnit.Case, async: false

  # Starts a KeyedAggregator under the test supervisor whose :on_flush callback
  # forwards each flushed key/batch back to the test process as
  # {:flushed, key, batch}.
  defp start_agg(opts) do
    test_pid = self()

    defaults = [on_flush: fn key, batch -> send(test_pid, {:flushed, key, batch}) end]

    child_opts = Keyword.merge(defaults, opts)
    start_supervised!({KeyedAggregator, child_opts})
  end

  # ---------------------------------------------------------------
  # Size-triggered flush (per key)
  # ---------------------------------------------------------------

  test "flushes a key when it reaches the configured batch size" do
    agg = start_agg(batch_size: 3, interval_ms: 30_000)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)

    assert_receive {:flushed, :a, [1, 2, 3]}, 1_000
  end

  test "batch_size of 1 flushes every event for a key immediately" do
    agg = start_agg(batch_size: 1, interval_ms: 30_000)

    KeyedAggregator.push(agg, :x, :first)
    assert_receive {:flushed, :x, [:first]}, 1_000

    KeyedAggregator.push(agg, :x, :second)
    assert_receive {:flushed, :x, [:second]}, 1_000
  end

  test "keys buffer and flush independently by size" do
    agg = start_agg(batch_size: 2, interval_ms: 30_000)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :b, 10)
    KeyedAggregator.push(agg, :a, 2)

    # :a reached batch size and flushes; :b has one buffered event, no flush.
    assert_receive {:flushed, :a, [1, 2]}, 1_000
    refute_receive {:flushed, :b, _}, 200
  end

  # ---------------------------------------------------------------
  # Time-triggered flush (per key)
  # ---------------------------------------------------------------

  test "flushes each key's partial batch on its own interval" do
    agg = start_agg(batch_size: 5, interval_ms: 300)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :b, 2)

    refute_receive {:flushed, _, _}, 100

    assert_receive {:flushed, :a, [1]}, 1_000
    assert_receive {:flushed, :b, [2]}, 1_000
  end

  test "does not flush empty keys on the interval" do
    start_agg(batch_size: 5, interval_ms: 150)

    refute_receive {:flushed, _, _}, 600
  end

  test "keeps aggregating a key after a time-triggered partial flush" do
    agg = start_agg(batch_size: 3, interval_ms: 200)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 1_000

    KeyedAggregator.push(agg, :a, 4)
    assert_receive {:flushed, :a, [4]}, 1_000

    KeyedAggregator.push(agg, :a, 5)
    assert_receive {:flushed, :a, [5]}, 1_000
  end

  # ---------------------------------------------------------------
  # Per-key timer reset
  # ---------------------------------------------------------------

  test "a key's interval timer resets after that key's size-triggered flush" do
    agg = start_agg(batch_size: 3, interval_ms: 600)

    # t ~= 0: buffer one event under :a (arms a timer with deadline t ~= 600).
    KeyedAggregator.push(agg, :a, 1)

    # Complete the batch well before that deadline to force a size flush.
    Process.sleep(250)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 1_000

    # New event for :a right after the flush (t ~= 250); deadline t ~= 850.
    KeyedAggregator.push(agg, :a, 4)

    # A stale timer from the first push would fire at t ~= 600 and flush [4].
    # With a correct reset that must not happen in the next ~400ms (t ~= 650).
    refute_receive {:flushed, :a, _}, 400

    # The re-armed timer flushes [4] ~600ms after the push at t ~= 250.
    assert_receive {:flushed, :a, [4]}, 800
  end

  test "flushing one key does not reset another key's timer" do
    agg = start_agg(batch_size: 2, interval_ms: 400)

    # :b starts its interval timer at t ~= 0 (deadline t ~= 400).
    KeyedAggregator.push(agg, :b, 100)

    # Well before :b's deadline, force a size flush of :a.
    Process.sleep(150)
    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    assert_receive {:flushed, :a, [1, 2]}, 1_000

    # :b must still flush on its ORIGINAL schedule (~400ms from t=0). If :a's
    # flush had reset it, :b would only fire ~400ms from t ~= 150 onwards; the
    # payload assertion below still pins the per-key isolation of the buffer.
    assert_receive {:flushed, :b, [100]}, 1_000
  end

  # ---------------------------------------------------------------
  # Documented defaults
  # ---------------------------------------------------------------

  test "defaults :batch_size to exactly 100 events per key" do
    # No :batch_size given, so the documented default of 100 applies; the
    # interval is pushed far out so only the size trigger can fire.
    agg = start_agg(interval_ms: 30_000)

    Enum.each(1..99, fn n -> KeyedAggregator.push(agg, :a, n) end)

    # 99 buffered events must NOT reach the default batch size.
    refute_receive {:flushed, :a, _}, 300

    KeyedAggregator.push(agg, :a, 100)

    # The 100th event completes the batch: exactly 100 events, in push order.
    assert_receive {:flushed, :a, batch}, 1_000
    assert batch == Enum.to_list(1..100)
  end

  test "defaults :interval_ms to exactly 1_000 ms for a key's time-triggered flush" do
    # No :interval_ms given, so the documented default of 1_000 ms applies; the
    # batch size is large enough that only the time trigger can fire.
    agg = start_agg(batch_size: 50)

    before_push = System.monotonic_time(:microsecond)
    KeyedAggregator.push(agg, :a, :only)
    assert_receive {:flushed, :a, [:only]}, 5_000
    elapsed_us = System.monotonic_time(:microsecond) - before_push

    # The key's timer is armed at (or after) the push, so a correct 1_000 ms
    # interval can never deliver the flush sooner than 1_000 ms after the push.
    # The upper bound leaves room for scheduler jitter while still ruling out
    # any other plausible default (500 ms, 2_000 ms, ...).
    assert elapsed_us >= 1_000_000
    assert elapsed_us < 1_500_000
  end

  test "defaults :on_flush to a no-op two-arity callback that keeps the server alive" do
    # Started with no :on_flush at all: the default callback must accept the
    # (key, batch) pair and simply do nothing, so a flush cannot crash the
    # aggregator.
    agg = start_supervised!({KeyedAggregator, [batch_size: 1, interval_ms: 100]})
    ref = Process.monitor(agg)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, {:tuple, "key"}, %{payload: :two})

    refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 500
    assert Process.alive?(agg)
  end

  test "a key's deadline stays anchored to the first push of the current batch" do
    agg = start_agg(batch_size: 10, interval_ms: 600)

    # t ~= 0: :a goes empty -> non-empty, arming its only timer (deadline t ~= 600).
    KeyedAggregator.push(agg, :a, 1)

    # t ~= 300: a second push into the already non-empty buffer must not move it.
    Process.sleep(300)
    KeyedAggregator.push(agg, :a, 2)

    # Nothing before the original deadline (t ~= 400 here).
    refute_receive {:flushed, :a, _}, 100

    # The anchored deadline fires at t ~= 600. A re-armed/extended timer would
    # instead fire at t ~= 900 and miss this window.
    assert_receive {:flushed, :a, [1, 2]}, 400
  end

  test "a key's next time flush is one interval after its next push, not after the flush" do
    agg = start_agg(batch_size: 5, interval_ms: 300)

    # t ~= 0 push, time-triggered flush at t ~= 300.
    KeyedAggregator.push(agg, :a, 1)
    assert_receive {:flushed, :a, [1]}, 1_000
    flushed_at = System.monotonic_time(:millisecond)

    # Next push for :a happens ~150ms after the flush. Its deadline must be one
    # full interval after THAT push, not 300ms after the flush.
    Process.sleep(150)
    KeyedAggregator.push(agg, :a, 2)

    # A timer anchored to the previous flush would fire ~300ms after `flushed_at`,
    # i.e. ~150ms from now. Nothing may arrive in that window.
    refute_receive {:flushed, :a, _}, 200
    assert System.monotonic_time(:millisecond) - flushed_at >= 300

    assert_receive {:flushed, :a, [2]}, 500
  end

  test "registers under :name and accepts pushes addressed to that name" do
    name = :"keyed_aggregator_named_#{System.unique_integer([:positive])}"
    start_agg(name: name, batch_size: 2, interval_ms: 30_000)

    assert is_pid(Process.whereis(name))

    assert KeyedAggregator.push(name, :a, 1) == :ok
    assert KeyedAggregator.push(name, :a, 2) == :ok

    assert_receive {:flushed, :a, [1, 2]}, 1_000
  end

  test "ignores unrelated messages without crashing or disturbing a key's buffer" do
    agg = start_agg(batch_size: 3, interval_ms: 30_000)
    mon = Process.monitor(agg)

    KeyedAggregator.push(agg, :a, 1)

    send(agg, :some_unrelated_message)
    send(agg, {:unexpected, :tuple, 42})
    send(agg, "a plain string")

    # No flush may be provoked by junk, and the process must stay up.
    refute_receive {:flushed, _, _}, 200
    refute_receive {:DOWN, ^mon, :process, _pid, _reason}, 100

    # The buffer for :a is untouched: the batch still completes in push order.
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 1_000
  end

  test "keeps duplicate events for a key rather than deduplicating them" do
    agg = start_agg(batch_size: 4, interval_ms: 30_000)

    Enum.each([:dup, :dup, :other, :dup], fn ev -> KeyedAggregator.push(agg, :k, ev) end)

    assert_receive {:flushed, :k, [:dup, :dup, :other, :dup]}, 1_000
  end

  test "start_link/0 works with no argument and still accepts pushes returning :ok" do
    {:ok, pid} = KeyedAggregator.start_link()
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.alive?(pid)
    assert KeyedAggregator.push(pid, {:any, "term"}, %{payload: [1, 2]}) == :ok
    assert Process.alive?(pid)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
