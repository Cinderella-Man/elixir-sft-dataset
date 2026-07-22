# Implement `handle_info/2` for the `Aggregator` GenServer

Implement the `handle_info/2` callback. It is the message handler that drives
**time-triggered flushing** for the aggregator.

The only meaningful message it needs to act on is the interval-timer message
`{:flush, ref}`, where `ref` is a unique reference created by `start_timer/1`
and tracked in the state under `:timer_ref`. Requirements:

- **Only honor the current timer.** Act on `{:flush, ref}` **only** when `ref`
  matches the `:timer_ref` currently stored in the state. Because a flush can be
  triggered by size before the interval elapses, an older timer may still fire
  and deliver a `{:flush, old_ref}` message whose `old_ref` no longer matches.
  Such stale timer messages must be ignored (return the state unchanged).
- **When the current timer fires:** if there are buffered events
  (`count > 0`), flush them via `flush/1`. If the buffer is empty, do **not**
  call the callback — just clear the timer with `clear_timer/1` so a fresh timer
  is started on the next push.
- **Ignore anything else.** Any other unexpected message must leave the state
  untouched.
- All clauses return the standard `{:noreply, state}` GenServer reply.

```elixir
defmodule Aggregator do
  @moduledoc """
  A `GenServer` that collects individual events and flushes them to a
  callback in batches.

  A flush is triggered when **either** of the following happens first:

    * the number of buffered events reaches `:batch_size`, or
    * `:interval_ms` milliseconds elapse since the last flush (or since
      start) while there are buffered events.

  Events are always delivered to the `:on_flush` callback as a list, in the
  exact order they were pushed.
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

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    state =
      state
      |> add_event(event)
      |> ensure_timer()

    state =
      if state.count >= state.batch_size do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    # TODO
  end

  ## Internal helpers

  defp add_event(state, event) do
    %{state | buffer: [event | state.buffer], count: state.count + 1}
  end

  # Start the interval timer only when the buffer transitions from empty to
  # non-empty. While buffered events remain, the timer keeps running until a
  # flush resets it.
  defp ensure_timer(%{timer: nil} = state), do: start_timer(state)
  defp ensure_timer(state), do: state

  defp start_timer(state) do
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
  # the buffer and the interval timer. After a flush the buffer is empty, so
  # the timer is left cleared and will be restarted on the next push.
  defp flush(%{count: 0} = state), do: state

  defp flush(state) do
    batch = Enum.reverse(state.buffer)
    state.on_flush.(batch)

    state
    |> clear_timer()
    |> Map.merge(%{buffer: [], count: 0})
  end
end
```