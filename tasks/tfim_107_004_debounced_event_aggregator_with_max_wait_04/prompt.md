# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DebounceAggregator do
  @moduledoc """
  A `GenServer` that collects individual events and flushes them to a callback
  in batches using a **debounce** strategy with a max-wait cap.

  A batch is flushed when the first of the following occurs:

    * `:idle_ms` elapse with no new pushes (the idle timer is reset on every
      push — debounce), or
    * `:max_wait_ms` elapse since the first event of the current batch was
      buffered (this timer is NOT reset by pushes, bounding total latency), or
    * the buffer reaches `:batch_size` events.

  Events are always delivered to the `:on_flush` callback as a list, in the
  exact order they were pushed.
  """

  use GenServer

  @default_idle_ms 1_000
  @default_max_wait_ms 5_000
  @default_batch_size :infinity
  @default_on_flush &DebounceAggregator.__noop__/1

  ## Public API

  @doc """
  Start a debounce aggregator process.

  ## Options

    * `:idle_ms` — positive integer milliseconds of quiet after which the batch
      is flushed; reset on every push. Defaults to `#{@default_idle_ms}`.
    * `:max_wait_ms` — positive integer milliseconds after the first event of a
      batch at which it is flushed regardless of activity. Defaults to
      `#{@default_max_wait_ms}`.
    * `:batch_size` — positive integer or `:infinity`; flush once this many events
      are buffered. Defaults to `:infinity`.
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
      idle_ms: Keyword.get(opts, :idle_ms, @default_idle_ms),
      max_wait_ms: Keyword.get(opts, :max_wait_ms, @default_max_wait_ms),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # Buffer stored in reverse push order; reversed at flush time.
      buffer: [],
      count: 0,
      # `gen` tags the current batch's timers so stale timer messages from a
      # superseded batch are ignored.
      gen: nil,
      idle_timer: nil,
      max_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    # A push into an empty buffer begins a new batch and arms the max-wait cap.
    state = if state.count == 0, do: start_batch(state), else: state

    state = %{state | buffer: [event | state.buffer], count: state.count + 1}

    # The idle timer is (re)armed on every push — this is the debounce.
    state = reset_idle(state)

    state =
      if size_reached?(state) do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:idle_flush, gen}, %{gen: gen} = state) when gen != nil do
    {:noreply, flush(state)}
  end

  def handle_info({:max_flush, gen}, %{gen: gen} = state) when gen != nil do
    {:noreply, flush(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  defp size_reached?(%{batch_size: :infinity}), do: false
  defp size_reached?(%{count: count, batch_size: size}), do: count >= size

  defp start_batch(state) do
    gen = make_ref()
    max_timer = Process.send_after(self(), {:max_flush, gen}, state.max_wait_ms)
    %{state | gen: gen, max_timer: max_timer}
  end

  defp reset_idle(state) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
    timer = Process.send_after(self(), {:idle_flush, state.gen}, state.idle_ms)
    %{state | idle_timer: timer}
  end

  # Deliver buffered events (in push order) to the callback and clear both timers
  # so the next push begins a brand-new batch.
  defp flush(%{count: 0} = state), do: state

  defp flush(state) do
    batch = Enum.reverse(state.buffer)
    state.on_flush.(batch)

    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
    if state.max_timer, do: Process.cancel_timer(state.max_timer)

    %{state | buffer: [], count: 0, gen: nil, idle_timer: nil, max_timer: nil}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DebounceAggregatorTest do
  use ExUnit.Case, async: false

  # Starts a DebounceAggregator under the test supervisor whose :on_flush
  # callback forwards each flushed batch back to the test process.
  defp start_agg(opts) do
    test_pid = self()

    defaults = [on_flush: fn batch -> send(test_pid, {:flushed, batch}) end]

    child_opts = Keyword.merge(defaults, opts)
    start_supervised!({DebounceAggregator, child_opts})
  end

  # ---------------------------------------------------------------
  # Idle (debounce) flush
  # ---------------------------------------------------------------

  test "flushes a coalesced batch after the stream goes idle" do
    agg = start_agg(idle_ms: 150, max_wait_ms: 5_000, batch_size: 1_000_000)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)

    # Still within the idle window, nothing yet.
    refute_receive {:flushed, _}, 80

    # After the stream is quiet for idle_ms, both events flush as one batch.
    assert_receive {:flushed, [:a, :b]}, 500
  end

  test "each push resets the idle timer (debounce)" do
    agg = start_agg(idle_ms: 200, max_wait_ms: 5_000, batch_size: 1_000_000)

    DebounceAggregator.push(agg, :a)

    # Push :b before :a's idle window elapses; this resets the idle timer.
    Process.sleep(120)
    DebounceAggregator.push(agg, :b)

    # Idle is measured from :b now, so no flush should have happened yet
    # (a naive timer keyed to :a would have fired around here).
    refute_receive {:flushed, _}, 120

    # After quiet from :b, both events flush together — proving :a was NOT
    # flushed alone at its original idle deadline.
    assert_receive {:flushed, [:a, :b]}, 400
  end

  # ---------------------------------------------------------------
  # Max-wait cap
  # ---------------------------------------------------------------

  test "max_wait bounds latency even while pushes keep arriving" do
    # TODO
  end

  # ---------------------------------------------------------------
  # Size flush
  # ---------------------------------------------------------------

  test "flushes immediately when the buffer reaches batch_size" do
    agg = start_agg(idle_ms: 5_000, max_wait_ms: 5_000, batch_size: 3)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)
    DebounceAggregator.push(agg, :c)

    assert_receive {:flushed, [:a, :b, :c]}, 500
  end

  # ---------------------------------------------------------------
  # No empty flushes / fresh batches
  # ---------------------------------------------------------------

  test "never flushes an empty batch" do
    start_agg(idle_ms: 100, max_wait_ms: 100, batch_size: 3)

    refute_receive {:flushed, _}, 400
  end

  test "starts a fresh batch after each flush" do
    agg = start_agg(idle_ms: 150, max_wait_ms: 5_000, batch_size: 3)

    # A size flush first.
    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)
    DebounceAggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 500

    # A leftover single event must flush on the idle timer of a fresh batch.
    DebounceAggregator.push(agg, :d)
    assert_receive {:flushed, [:d]}, 500

    # And it keeps working afterwards.
    DebounceAggregator.push(agg, :e)
    assert_receive {:flushed, [:e]}, 500
  end

  test "a batch that follows a max-wait flush gets a fresh max-wait timer" do
    agg = start_agg(idle_ms: 400, max_wait_ms: 250, batch_size: 1_000_000)

    # First batch ends on its max-wait cap (250 < idle 400).
    DebounceAggregator.push(agg, :a)
    assert_receive {:flushed, [:a]}, 600

    # Second batch: push faster than idle_ms so the idle timer can never fire.
    # Only a freshly armed max-wait timer can end this batch.
    DebounceAggregator.push(agg, :b)
    Process.sleep(100)
    DebounceAggregator.push(agg, :c)
    Process.sleep(100)
    DebounceAggregator.push(agg, :d)

    assert_receive {:flushed, [:b, :c, :d]}, 500
  end

  test "default batch_size of infinity applies no size trigger" do
    agg = start_agg(idle_ms: 150, max_wait_ms: 5_000)

    for event <- [:a, :b, :c, :d, :e], do: DebounceAggregator.push(agg, event)

    # No size flush may split the burst; the whole burst coalesces on idle.
    assert_receive {:flushed, [:a, :b, :c, :d, :e]}, 500
    refute_receive {:flushed, _}, 200
  end

  test "registers under :name and accepts pushes addressed to that name" do
    start_agg(name: :promise_named_aggregator, idle_ms: 120, max_wait_ms: 5_000)

    assert is_pid(Process.whereis(:promise_named_aggregator))

    DebounceAggregator.push(:promise_named_aggregator, :a)
    DebounceAggregator.push(:promise_named_aggregator, :b)

    assert_receive {:flushed, [:a, :b]}, 500
  end

  test "default on_flush is a no-op that does not crash the aggregator" do
    agg = start_supervised!({DebounceAggregator, [idle_ms: 80, max_wait_ms: 200]})
    ref = Process.monitor(agg)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)

    # The default flush callback must swallow the batch without dying.
    refute_receive {:DOWN, ^ref, :process, _, _}, 400
    assert Process.alive?(agg)

    # And the aggregator keeps accepting work after the no-op flush.
    assert DebounceAggregator.push(agg, :c) == :ok
    refute_receive {:DOWN, ^ref, :process, _, _}, 300
  end

  test "push returns :ok immediately without waiting for a flush" do
    agg = start_agg(idle_ms: 5_000, max_wait_ms: 5_000, batch_size: 1_000_000)

    assert DebounceAggregator.push(agg, :a) == :ok
    assert DebounceAggregator.push(agg, :b) == :ok

    # Neither timer has expired, so push clearly did not block on a flush.
    refute_receive {:flushed, _}, 150
  end

  test "batch_size of one flushes every event as its own batch" do
    agg = start_agg(idle_ms: 5_000, max_wait_ms: 5_000, batch_size: 1)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)

    assert_receive {:flushed, [:a]}, 500
    assert_receive {:flushed, [:b]}, 500
  end
end
```
