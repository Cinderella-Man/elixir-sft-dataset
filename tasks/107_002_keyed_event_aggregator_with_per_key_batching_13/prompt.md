# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Keyed Event Aggregator with Per-Key Batched Flushing

Write me an Elixir `GenServer` module called `KeyedAggregator` that collects
individual events **partitioned by key** and flushes each key's events to a
callback in batches. Every key maintains its **own independent buffer and its own
flush timer**. A key is flushed when **either** that key's batch reaches a
configurable size **or** a configurable time interval elapses while that key has
buffered events — whichever comes first.

## Public API

- `KeyedAggregator.start_link(opts)` — start the process. `opts` is a keyword list
  (it must also be callable as `start_link()` with no argument, defaulting to `[]`)
  that supports:
  - `:batch_size` — a positive integer. When the number of buffered events for a
    given key reaches this value, flush that key immediately. Defaults to `100`.
  - `:interval_ms` — a positive integer number of milliseconds. If this much time
    passes while a key still has buffered events, flush that key. Defaults to
    `1_000`.
  - `:on_flush` — a **two-arity** function called as `on_flush.(key, batch)` each
    time a key is flushed, where `batch` is the list of events for that key.
    Defaults to a no-op function.
  - `:name` — an optional name for process registration. When present it is passed
    through to `GenServer.start_link/3` as `[name: name]`; when absent the process
    is started unnamed. `:name` is a start-time concern only and must not be
    treated as aggregator configuration.

  Returns whatever `GenServer.start_link/3` returns (`{:ok, pid}`, or
  `{:error, {:already_started, pid}}` for a name clash, etc.). Options do not need
  to be validated: callers are trusted to pass sane values.

  The module must also be startable as a **supervised child** using the standard
  `{KeyedAggregator, opts}` child specification (i.e. it must provide a
  `child_spec/1` that starts the process via `start_link(opts)` with the given
  keyword list), so it can be placed under a supervisor or launched with
  `start_supervised!/1`.

- `KeyedAggregator.push(server, key, event)` — buffer a single `event` under `key`
  on the aggregator referenced by `server` (a pid or a registered name). This is
  **asynchronous** (fire-and-forget): it always returns `:ok` immediately, before
  any flushing or callback invocation has necessarily happened, and it never
  returns an error tuple. Both `key` and `event` may be **any term**.

## Behavior requirements

1. **Per-key ordering.** Events for a key must be delivered to the callback in the
   exact order they were pushed for that key. Pushing `1` then `2` then `3` under
   key `:a` and flushing yields `on_flush.(:a, [1, 2, 3])`. Duplicate events are
   kept as-is; nothing is deduplicated. The batch handed to the callback is always
   a plain list of the buffered events, never wrapped or annotated.

2. **Implicit key creation.** There is no "register a key" step. The first `push`
   for a previously unseen key (or for a key that has already been flushed away)
   creates a fresh empty buffer for it. Any term is a valid key; there is no
   limit on the number of distinct keys.

3. **Per-key size-triggered flush.** As soon as a key's buffered event count
   **reaches** `:batch_size` (i.e. count `>= batch_size`, checked after each push),
   flush that key by calling `on_flush.(key, batch)`. The flush happens while
   handling that very push, so a batch of exactly `:batch_size` events is emitted —
   never more. With `batch_size: 1`, every push flushes immediately with a
   one-element batch.

4. **Per-key time-triggered flush.** Each key has its own interval timer. The timer
   for a key is armed **when that key's buffer goes from empty to non-empty** —
   that is, on the first push for the key after it was last flushed (or on its very
   first push ever) — and it is scheduled to fire `:interval_ms` later. Subsequent
   pushes into an already non-empty buffer do **not** re-arm, extend, or restart
   that key's timer: the deadline stays anchored to the first push of the current
   batch. When the timer fires and the key has buffered events, flush that key.

5. **No empty flushes.** The callback is never invoked with an empty batch. If a
   key has no buffered events, no time-based flush happens for it — a key that has
   been flushed and not pushed to again simply goes quiet and stops firing timers
   until it is pushed to again.

6. **Full reset after every flush.** Flushing a key — for *either* reason —
   completely resets that key: its buffer becomes empty, its count returns to zero,
   and its pending interval timer is cancelled. A size-triggered flush must cancel
   the key's outstanding timer so that no spurious flush attempt happens later for
   the events that were just delivered; a leftover/stale timer message for a key
   must be ignored rather than producing a duplicate, empty, or partial flush.
   After a flush, the *next* time-based flush of that key is a full `:interval_ms`
   after the key's next push (per requirement 4), not `:interval_ms` after the
   flush itself.

7. **Keys are independent.** Flushing one key (by size or by time) must not flush,
   clear, or reset the buffer, count, or timer of any other key. Each key's batch
   is delivered in its own `on_flush.(key, batch)` call — batches from different
   keys are never merged into one call.

8. **Callback execution.** `on_flush` is invoked from inside the aggregator process
   while it handles the push or timer that triggered the flush, so flushes are
   serialized: one callback call completes before the next message is handled. The
   callback's return value is ignored. There is no requirement to trap, rescue, or
   otherwise defend against a callback that raises.

9. **Unrelated messages.** Any message the aggregator receives that is not a push
   or one of its own live flush timers must be ignored, leaving the state
   unchanged (no crash, no flush).

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.

## The module with `start_link` missing

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

  def start_link(opts \\ []) when is_list(opts) do
    # TODO
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

Give me only the complete implementation of `start_link` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
