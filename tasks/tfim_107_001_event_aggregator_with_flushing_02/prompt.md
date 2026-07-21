# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Aggregator do
  @moduledoc """
  A `GenServer` that collects individual events and flushes them to a
  callback in batches.

  A flush is triggered when **either** of the following happens first:

    * the number of buffered events reaches `:batch_size`, or
    * `:interval_ms` milliseconds elapse since the last flush (or since
      start) while there are buffered events.

  The interval is anchored on the most recent flush (or on start, if no
  flush has happened yet) — not on the moment an event is pushed. Events
  are always delivered to the `:on_flush` callback as a list, in the exact
  order they were pushed.
  """

  use GenServer

  @default_batch_size 100
  @default_interval_ms 1_000
  @default_on_flush &Aggregator.__noop__/1

  ## Public API

  @doc """
  Start an aggregator process.

  ## Options

    * `:batch_size` — positive integer, flush once this many events are
      buffered. Defaults to `#{@default_batch_size}`.
    * `:interval_ms` — positive integer number of milliseconds after which a
      non-empty buffer is flushed. Defaults to `#{@default_interval_ms}`.
    * `:on_flush` — one-arity function called with the batch (a list) on each
      flush. Defaults to a no-op.
    * `:name` — optional registration name, passed to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Buffer a single `event`. Asynchronous; always returns `:ok` immediately.
  """
  @spec push(GenServer.server(), term()) :: :ok
  def push(server, event) do
    GenServer.cast(server, {:push, event})
  end

  @doc false
  def __noop__(_batch), do: :ok

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # Buffer is stored in reverse push order for O(1) prepend; it is
      # reversed into push order right before being handed to the callback.
      buffer: [],
      count: 0,
      timer: nil,
      timer_ref: nil
    }

    # The interval clock runs from start, independently of when events are
    # pushed, and is restarted on every flush.
    {:ok, start_timer(state)}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    state = add_event(state, event)

    state =
      if state.count >= state.batch_size do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:flush, ref}, %{timer_ref: ref} = state) do
    # Only act on the timer we are currently tracking; stale timer messages
    # (from a timer that was already superseded by a flush) carry an old ref
    # and are ignored below.
    state =
      if state.count > 0 do
        flush(state)
      else
        # Nothing buffered: never call the callback, just wait another
        # interval.
        start_timer(state)
      end

    {:noreply, state}
  end

  def handle_info({:flush, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  defp add_event(state, event) do
    %{state | buffer: [event | state.buffer], count: state.count + 1}
  end

  defp start_timer(state) do
    state = clear_timer(state)
    ref = make_ref()
    timer = Process.send_after(self(), {:flush, ref}, state.interval_ms)
    %{state | timer: timer, timer_ref: ref}
  end

  defp clear_timer(%{timer: nil} = state), do: state

  defp clear_timer(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil, timer_ref: nil}
  end

  # Deliver the buffered events (in push order) to the callback, then reset
  # the buffer and restart the interval timer, so the next time-based flush
  # is due a full interval after this one.
  defp flush(%{count: 0} = state), do: state

  defp flush(state) do
    batch = Enum.reverse(state.buffer)
    state.on_flush.(batch)

    state
    |> Map.merge(%{buffer: [], count: 0})
    |> start_timer()
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule AggregatorTest do
  use ExUnit.Case, async: false

  # Starts an Aggregator under the test supervisor whose :on_flush callback
  # forwards each flushed batch back to the test process as {:flushed, batch}.
  defp start_agg(opts) do
    test_pid = self()

    defaults = [on_flush: fn batch -> send(test_pid, {:flushed, batch}) end]

    child_opts = Keyword.merge(defaults, opts)
    start_supervised!({Aggregator, child_opts})
  end

  # ---------------------------------------------------------------
  # Size-triggered flush
  # ---------------------------------------------------------------

  test "flushes immediately when the batch reaches the configured size" do
    # TODO
  end

  test "batch_size of 1 flushes every event immediately" do
    agg = start_agg(batch_size: 1, interval_ms: 5_000)

    Aggregator.push(agg, :x)
    assert_receive {:flushed, [:x]}, 500

    Aggregator.push(agg, :y)
    assert_receive {:flushed, [:y]}, 500
  end

  test "multiple full batches flush in order with fresh buffers" do
    agg = start_agg(batch_size: 2, interval_ms: 5_000)

    Aggregator.push(agg, 1)
    Aggregator.push(agg, 2)
    Aggregator.push(agg, 3)
    Aggregator.push(agg, 4)

    assert_receive {:flushed, [1, 2]}, 500
    assert_receive {:flushed, [3, 4]}, 500
  end

  # ---------------------------------------------------------------
  # Time-triggered flush
  # ---------------------------------------------------------------

  test "flushes buffered events after the interval when below batch size" do
    agg = start_agg(batch_size: 5, interval_ms: 200)

    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)

    # Below batch size, so nothing should flush right away.
    refute_receive {:flushed, _}, 80

    # Eventually the interval elapses and the partial batch is flushed.
    assert_receive {:flushed, [:a, :b]}, 500
  end

  test "does not flush empty batches on the interval" do
    start_agg(batch_size: 5, interval_ms: 150)

    # No pushes at all — the callback must never be invoked, even across
    # multiple interval periods.
    refute_receive {:flushed, _}, 400
  end

  test "keeps aggregating after a time-triggered partial flush" do
    agg = start_agg(batch_size: 3, interval_ms: 150)

    # First a size flush.
    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 500

    # Then a leftover single event that must flush on the timer.
    Aggregator.push(agg, :d)
    assert_receive {:flushed, [:d]}, 500

    # And it keeps working afterwards.
    Aggregator.push(agg, :e)
    assert_receive {:flushed, [:e]}, 500
  end

  # ---------------------------------------------------------------
  # Timer reset after each flush
  # ---------------------------------------------------------------

  test "the interval timer resets after a size-triggered flush" do
    # interval 400ms, batch size 3.
    agg = start_agg(batch_size: 3, interval_ms: 400)

    # t ~= 0: buffer one event.
    Aggregator.push(agg, :a)

    # Wait ~200ms (half the interval), then complete the batch to force a
    # size-triggered flush at t ~= 200ms.
    Process.sleep(200)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 300

    # Immediately push a new event (t ~= 200ms).
    Aggregator.push(agg, :d)

    # If the timer had NOT been reset, a stale timer from start would fire at
    # t ~= 400ms and flush [:d]. Assert that does NOT happen within the next
    # ~300ms (up to t ~= 500ms).
    refute_receive {:flushed, _}, 300

    # With a correct reset, the flush for [:d] happens ~400ms after the flush
    # at t ~= 200ms, i.e. around t ~= 600ms.
    assert_receive {:flushed, [:d]}, 400
  end

  # ---------------------------------------------------------------
  # Option defaults
  # ---------------------------------------------------------------

  test "batch_size defaults to 100 when not provided" do
    # Long interval so only the size trigger can fire; :batch_size omitted.
    agg = start_agg(interval_ms: 5_000)

    Enum.each(1..99, fn n -> Aggregator.push(agg, n) end)

    # 99 buffered events is still one short of the documented default of 100.
    refute_receive {:flushed, _}, 200

    Aggregator.push(agg, 100)

    assert_receive {:flushed, batch}, 500
    assert batch == Enum.to_list(1..100)
  end

  test "interval_ms defaults to 1_000 when not provided" do
    # Batch size large enough that only the time trigger can fire.
    agg = start_agg(batch_size: 50)

    Aggregator.push(agg, :a)

    # A default of 1_000ms means no flush is due yet at ~700ms.
    refute_receive {:flushed, _}, 700

    # But the partial batch must be flushed once the default interval elapses.
    assert_receive {:flushed, [:a]}, 800
  end

  test "on_flush defaults to a no-op so the aggregator survives flushes without it" do
    # No :on_flush given at all: flushing must not crash the process.
    agg = start_supervised!({Aggregator, [batch_size: 2, interval_ms: 100]})
    ref = Process.monitor(agg)

    # Force a size-triggered flush, then a time-triggered flush of a leftover.
    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)

    refute_receive {:DOWN, ^ref, :process, ^agg, _reason}, 500
    assert Process.alive?(agg)
  end

  # ---------------------------------------------------------------
  # Name registration
  # ---------------------------------------------------------------

  test "registers under :name and accepts pushes addressed to that name" do
    name = :"aggregator_#{System.pid()}_#{System.unique_integer([:positive])}"

    pid = start_agg(name: name, batch_size: 2, interval_ms: 5_000)

    assert Process.whereis(name) == pid

    # push/2 must accept the registered name, not just a pid.
    Aggregator.push(name, :a)
    Aggregator.push(name, :b)

    assert_receive {:flushed, [:a, :b]}, 500
  end

  test "time-based flush is due a full interval after the flush, even if the event is pushed late" do
    # Interval 400ms, batch size 2 so we can force a size flush at t ~= 0.
    agg = start_agg(batch_size: 2, interval_ms: 400)

    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    assert_receive {:flushed, [:a, :b]}, 500

    # The most recent flush happened at t ~= 0, so the next time-based flush is
    # due at t ~= 400 — regardless of when the event that fills the buffer
    # arrives. Push :c at t ~= 250, i.e. only ~150ms before that deadline.
    Process.sleep(250)
    Aggregator.push(agg, :c)

    # Anchored on the flush (as promised), [:c] flushes ~150ms from now.
    # Anchored on the push instead, it would take a further ~400ms.
    assert_receive {:flushed, [:c]}, 280
  end

  test "time-based flush is due a full interval after start when the first event arrives late" do
    # Batch size high enough that only the time trigger can fire.
    agg = start_agg(batch_size: 5, interval_ms: 400)

    # No flush has happened yet, so the interval is measured from start:
    # the deadline is t ~= 400. Buffer an event at t ~= 250.
    Process.sleep(250)
    Aggregator.push(agg, :a)

    # Measured from start (as promised), [:a] flushes ~150ms from now.
    # Measured from the push instead, it would take a further ~400ms.
    assert_receive {:flushed, [:a]}, 280
  end

  test "push returns :ok for both a pid and a registered name" do
    name = :"aggregator_push_ret_#{System.unique_integer([:positive])}"

    pid = start_agg(name: name, batch_size: 5, interval_ms: 5_000)

    assert Aggregator.push(pid, :a) == :ok
    assert Aggregator.push(name, :b) == :ok
  end

  # ---------------------------------------------------------------
  # The interval fires on its own
  # ---------------------------------------------------------------

  test "the aggregator flushes on its own schedule with no external trigger" do
    # 25ms interval, batch size far out of reach: the only thing that can ever
    # deliver this event is the aggregator's own elapsed-interval flush.
    agg = start_agg(batch_size: 1_000, interval_ms: 25)

    Aggregator.push(agg, :tick)

    assert_receive {:flushed, [:tick]}, 2_000
  end

  test "a second interval flush follows the first without any further prompting" do
    agg = start_agg(batch_size: 1_000, interval_ms: 25)

    Aggregator.push(agg, :first)
    assert_receive {:flushed, [:first]}, 2_000

    # The timer keeps running after a flush, so a later event is picked up by
    # the next automatic firing too.
    Aggregator.push(agg, :second)
    assert_receive {:flushed, [:second]}, 2_000
  end

  # ---------------------------------------------------------------
  # Starting with no options
  # ---------------------------------------------------------------

  test "starts with an empty option list and keeps accepting pushes" do
    # Every option is optional, so a bare start must succeed and stay healthy.
    agg = start_supervised!({Aggregator, []})
    ref = Process.monitor(agg)

    assert Aggregator.push(agg, :a) == :ok
    assert Aggregator.push(agg, :b) == :ok

    refute_receive {:DOWN, ^ref, :process, ^agg, _reason}, 300
    assert Process.alive?(agg)
  end

  test "a :name registration is honoured for non-atom names passed to GenServer" do
    gname = {:global, :"aggregator_global_#{System.pid()}_#{System.unique_integer([:positive])}"}

    start_agg(name: gname, batch_size: 2, interval_ms: 5_000)

    # :name is handed straight to GenServer.start_link/3, so any server name it
    # accepts must work for registration and for push/2.
    assert Aggregator.push(gname, :a) == :ok
    Aggregator.push(gname, :b)

    assert_receive {:flushed, [:a, :b]}, 500
  end
end
```
