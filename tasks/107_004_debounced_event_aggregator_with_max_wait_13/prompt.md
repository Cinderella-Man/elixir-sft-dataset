# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `push` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Debounced Event Aggregator with Max-Wait

Write me an Elixir `GenServer` module called `DebounceAggregator` that collects
individual events and flushes them to a callback in batches, using a **debounce**
strategy: the aggregator waits for the stream to go quiet before flushing, but also
guarantees an upper bound on how long any event waits.

Concretely, a batch is flushed when **any** of the following happens first:

- **Idle:** `:idle_ms` elapse with no new pushes (the stream went quiet), or
- **Max-wait:** `:max_wait_ms` elapse since the *first* event of the current batch
  was buffered (a busy stream can't be delayed forever), or
- **Size:** the buffer reaches `:batch_size` events.

The key difference from a plain interval flush is that the **idle timer resets on
every push** (debounce), while the max-wait timer, started when a batch begins,
does **not** reset — it caps total latency for a continuously active stream.

## Public API

- `DebounceAggregator.start_link(opts)` — start the process. `opts` is a keyword
  list that supports:
  - `:idle_ms` — a positive integer number of milliseconds of quiet (no pushes)
    after which the current batch is flushed. Reset on every push. Defaults to
    `1_000`.
  - `:max_wait_ms` — a positive integer number of milliseconds after the first
    event of a batch was buffered, at which the batch is flushed regardless of
    ongoing activity. Defaults to `5_000`.
  - `:batch_size` — a positive integer or the atom `:infinity`. When the buffer
    reaches this many events, flush immediately. Defaults to `:infinity` (no
    size trigger).
  - `:on_flush` — a one-arity function called with the batch (a list of events)
    each time a flush occurs. Defaults to a no-op function.
  - `:name` — an optional name for process registration, passed through to
    `GenServer.start_link/3`.

- `DebounceAggregator.push(server, event)` — buffer a single `event` on the
  aggregator referenced by `server` (a pid or a registered name). This is
  asynchronous and returns `:ok` immediately.

## Behavior requirements

1. **Ordering.** Events must be delivered to the `:on_flush` callback as a list in
   the exact order they were pushed.

2. **Idle-triggered (debounce) flush.** Each push resets the idle timer to a fresh
   `:idle_ms`. Only after `:idle_ms` pass with no further pushes is the buffered
   batch flushed. So a rapid burst of pushes coalesces into a single batch flushed
   shortly after the burst ends.

3. **Max-wait cap.** When a new batch begins (a push into an empty buffer), start a
   max-wait timer for `:max_wait_ms`. This timer is **not** reset by subsequent
   pushes. If it fires while events are buffered, flush them. This bounds the
   latency of the oldest buffered event even if pushes never stop.

4. **Size-triggered flush.** If the buffer reaches `:batch_size` events, flush
   immediately. With the default `:infinity` there is no size trigger.

5. **No empty flushes.** A flush never invokes the callback with an empty batch.

6. **Fresh batch after every flush.** After any flush (idle, max-wait, or size),
   both timers are cleared. The next push starts a brand-new batch with a fresh
   idle timer and a fresh max-wait timer.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.

## The module with `push` missing

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

  def push(server, event) do
    # TODO
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

Give me only the complete implementation of `push` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
