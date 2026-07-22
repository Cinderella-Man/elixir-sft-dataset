# Implement `handle_cast/2`

Implement the `handle_cast/2` GenServer callback that handles the `{:push, event}`
message produced by `Aggregator.push/2`. It should append the incoming `event` to the
buffer using `add_event/2` and make sure the interval timer is running via
`ensure_timer/1` (which only starts a timer when the buffer transitions from empty to
non-empty). After buffering, check whether the buffered `count` has reached
`batch_size`; if so, flush the batch immediately using `flush/1` (which delivers the
events in push order, invokes the `on_flush` callback, and resets both the buffer and
the timer). Otherwise leave the state as-is. In all cases return `{:noreply, state}`
with the updated state.

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
    # TODO
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
        clear_timer(state)
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