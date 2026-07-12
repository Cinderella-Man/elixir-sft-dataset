# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Keyed Event Aggregator with Per-Key Batched Flushing

Write me an Elixir `GenServer` module called `KeyedAggregator` that collects
individual events **partitioned by key** and flushes each key's events to a
callback in batches. Every key maintains its **own independent buffer and its own
flush timer**. A key is flushed when **either** that key's batch reaches a
configurable size **or** a configurable time interval elapses since that key's
last flush — whichever comes first.

## Public API

- `KeyedAggregator.start_link(opts)` — start the process. `opts` is a keyword list
  that supports:
  - `:batch_size` — a positive integer. When the number of buffered events for a
    given key reaches this value, flush that key immediately. Defaults to `100`.
  - `:interval_ms` — a positive integer number of milliseconds. If this much time
    passes since a key's last flush (or since the key first started buffering)
    while that key still has buffered events, flush that key. Defaults to `1_000`.
  - `:on_flush` — a **two-arity** function called as `on_flush.(key, batch)` each
    time a key is flushed, where `batch` is the list of events for that key.
    Defaults to a no-op function.
  - `:name` — an optional name for process registration, passed through to
    `GenServer.start_link/3`.

- `KeyedAggregator.push(server, key, event)` — buffer a single `event` under `key`
  on the aggregator referenced by `server` (a pid or a registered name). This is
  asynchronous and returns `:ok` immediately.

## Behavior requirements

1. **Per-key ordering.** Events for a key must be delivered to the callback in the
   exact order they were pushed for that key. Pushing `1` then `2` then `3` under
   key `:a` and flushing yields `on_flush.(:a, [1, 2, 3])`.

2. **Per-key size-triggered flush.** As soon as a key's buffered event count
   reaches `:batch_size`, flush that key by calling `on_flush.(key, batch)`, then
   start a fresh empty buffer for that key.

3. **Per-key time-triggered flush.** Each key has its own interval timer. If
   `:interval_ms` elapses and a key has buffered events, flush that key.

4. **No empty flushes.** If a key's interval elapses while its buffer is empty, do
   **not** call the callback for that key.

5. **Per-key timer reset after every flush.** A key's interval timer is reset
   whenever that key is flushed for *either* reason. The next time-based flush of a
   key must happen a full `:interval_ms` after that key's most recent flush.

6. **Keys are independent.** Flushing one key (by size or time) must not flush,
   clear, or reset the timer of any other key.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.

## The buggy module

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
      if entry.count > state.batch_size do
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

## Failing test report

```
3 of 8 test(s) failed:

  * test flushes a key when it reaches the configured batch size
      
      
      Assertion failed, no matching message after 500ms
           The process mailbox is empty.
      code: assert_receive {:flushed, :a, [1, 2, 3]}
      

  * test batch_size of 1 flushes every event for a key immediately
      
      
      Assertion failed, no matching message after 500ms
           The process mailbox is empty.
      code: assert_receive {:flushed, :x, [:first]}
      

  * test keys buffer and flush independently by size
      
      
      Assertion failed, no matching message after 500ms
           The process mailbox is empty.
      code: assert_receive {:flushed, :a, [1, 2]}
```
