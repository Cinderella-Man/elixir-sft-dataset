# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule KeyedAggregator do
  @moduledoc """
  A `GenServer` that collects individual events partitioned by key and flushes
  each key's events to a callback in batches.

  Each key maintains its own independent buffer and its own interval timer. A
  key is flushed when **either**:

    * the number of buffered events for that key reaches `:batch_size`, or
    * `:interval_ms` milliseconds elapse since that key's last flush (or since
      the key first started buffering) while it still has buffered events.

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
    agg = start_agg(batch_size: 3, interval_ms: 5_000)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)

    assert_receive {:flushed, :a, [1, 2, 3]}, 500
  end

  test "batch_size of 1 flushes every event for a key immediately" do
    agg = start_agg(batch_size: 1, interval_ms: 5_000)

    KeyedAggregator.push(agg, :x, :first)
    assert_receive {:flushed, :x, [:first]}, 500

    KeyedAggregator.push(agg, :x, :second)
    assert_receive {:flushed, :x, [:second]}, 500
  end

  test "keys buffer and flush independently by size" do
    # TODO
  end

  # ---------------------------------------------------------------
  # Time-triggered flush (per key)
  # ---------------------------------------------------------------

  test "flushes each key's partial batch on its own interval" do
    agg = start_agg(batch_size: 5, interval_ms: 200)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :b, 2)

    refute_receive {:flushed, _, _}, 80

    assert_receive {:flushed, :a, [1]}, 500
    assert_receive {:flushed, :b, [2]}, 500
  end

  test "does not flush empty keys on the interval" do
    start_agg(batch_size: 5, interval_ms: 150)

    refute_receive {:flushed, _, _}, 400
  end

  test "keeps aggregating a key after a time-triggered partial flush" do
    agg = start_agg(batch_size: 3, interval_ms: 150)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 500

    KeyedAggregator.push(agg, :a, 4)
    assert_receive {:flushed, :a, [4]}, 500

    KeyedAggregator.push(agg, :a, 5)
    assert_receive {:flushed, :a, [5]}, 500
  end

  # ---------------------------------------------------------------
  # Per-key timer reset
  # ---------------------------------------------------------------

  test "a key's interval timer resets after that key's size-triggered flush" do
    agg = start_agg(batch_size: 3, interval_ms: 400)

    # t ~= 0: buffer one event under :a.
    KeyedAggregator.push(agg, :a, 1)

    # Complete the batch at t ~= 200 to force a size-triggered flush.
    Process.sleep(200)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 300

    # New event for :a right after the flush (t ~= 200).
    KeyedAggregator.push(agg, :a, 4)

    # A stale timer from the start would fire at t ~= 400 and flush [4]. With a
    # correct reset, that does NOT happen within the next ~300ms.
    refute_receive {:flushed, :a, _}, 300

    # The reset timer flushes [4] ~400ms after the flush at t ~= 200.
    assert_receive {:flushed, :a, [4]}, 400
  end

  test "flushing one key does not reset another key's timer" do
    agg = start_agg(batch_size: 2, interval_ms: 250)

    # :b starts its interval timer at t ~= 0.
    KeyedAggregator.push(agg, :b, 100)

    # Halfway through :b's interval, force a size flush of :a.
    Process.sleep(150)
    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    assert_receive {:flushed, :a, [1, 2]}, 300

    # :b must still flush on its ORIGINAL schedule (~250ms from t=0), not be
    # reset by :a's flush.
    assert_receive {:flushed, :b, [100]}, 300
  end
end
```
