# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule KeyedAggregator do
  @moduledoc """
  A `GenServer` that collects individual events partitioned by key and flushes
  each key's events to a callback in batches.

  Each key maintains its own independent buffer and its own interval timer. A
  key is flushed when **either**:

    * the number of buffered events for that key reaches `:batch_size`, or
    * `:interval_ms` milliseconds elapse since the key started buffering its
      CURRENT batch — the timer arms when a push turns an empty key non-empty,
      never from the previous flush — while it still has buffered events.

  Events for a key are always delivered to the `:on_flush` callback as a list,
  in the exact order they were pushed for that key, via `on_flush.(key, batch)`.
  """

  use GenServer

  @default_batch_size 100
  @default_interval_ms 1_000
  @default_on_flush &KeyedAggregator.__noop__/2

  ## Public API

  @doc """
  Start a keyed aggregator process.

  ## Options

    * `:batch_size` — positive integer, flush a key once this many events are
      buffered for it. Defaults to `#{@default_batch_size}`.
    * `:interval_ms` — positive integer milliseconds after which a key's
      non-empty buffer is flushed. Defaults to `#{@default_interval_ms}`.
    * `:on_flush` — two-arity function called as `on_flush.(key, batch)` on each
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
  Buffer a single `event` under `key`. Asynchronous; always returns `:ok`.
  """
  @spec push(GenServer.server(), term(), term()) :: :ok
  def push(server, key, event) do
    GenServer.cast(server, {:push, key, event})
  end

  @doc false
  def __noop__(_key, _batch), do: :ok

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # key => %{buffer, count, timer, timer_ref}
      keys: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, key, event}, state) do
    entry = Map.get(state.keys, key, new_entry())

    # Buffers are stored in reverse push order for O(1) prepend and reversed
    # into push order right before being handed to the callback.
    entry = %{entry | buffer: [event | entry.buffer], count: entry.count + 1}
    entry = ensure_timer(entry, key, state.interval_ms)

    state =
      if entry.count >= state.batch_size do
        flush_key(state, key, entry)
      else
        put_entry(state, key, entry)
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:flush, key, ref}, state) do
    # Only act on the timer we are currently tracking for this key; stale timer
    # messages (superseded by a flush) carry an old ref and are ignored.
    state =
      case Map.get(state.keys, key) do
        %{timer_ref: ^ref} = entry ->
          if entry.count > 0 do
            flush_key(state, key, entry)
          else
            put_entry(state, key, clear_timer(entry))
          end

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Internal helpers

  defp new_entry, do: %{buffer: [], count: 0, timer: nil, timer_ref: nil}

  defp put_entry(state, key, entry) do
    %{state | keys: Map.put(state.keys, key, entry)}
  end

  # Start a key's interval timer only on the transition from empty to non-empty.
  defp ensure_timer(%{timer: nil} = entry, key, interval_ms) do
    ref = make_ref()
    timer = Process.send_after(self(), {:flush, key, ref}, interval_ms)
    %{entry | timer: timer, timer_ref: ref}
  end

  defp ensure_timer(entry, _key, _interval_ms), do: entry

  defp clear_timer(%{timer: nil} = entry), do: entry

  defp clear_timer(entry) do
    Process.cancel_timer(entry.timer)
    %{entry | timer: nil, timer_ref: nil}
  end

  # Deliver a key's buffered events (in push order) to the callback, cancel that
  # key's timer, and drop the key so it starts fresh on the next push. Only this
  # key is touched — other keys and their timers are untouched.
  defp flush_key(state, key, entry) do
    batch = Enum.reverse(entry.buffer)
    state.on_flush.(key, batch)
    clear_timer(entry)
    %{state | keys: Map.delete(state.keys, key)}
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
