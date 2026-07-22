# Implement `handle_info/2` for `KeyedAggregator`

`KeyedAggregator` is a `GenServer` that buffers events partitioned by key and
flushes each key's buffer to an `on_flush.(key, batch)` callback either when the
key's batch reaches `:batch_size` or when the key's own interval timer fires.
Each key stores an entry of the shape
`%{buffer: [...], count: n, timer: timer_ref_or_nil, timer_ref: ref_or_nil}` in
`state.keys`, and every key has its own `Process.send_after/3` timer that sends a
`{:flush, key, ref}` message when `:interval_ms` elapses.

Implement the `handle_info/2` callback that reacts to those timer messages.

It must:

1. Handle the `{:flush, key, ref}` timer message:
   - Look up the current entry for `key` in `state.keys`.
   - Only act when the entry's `timer_ref` matches the incoming `ref`. This
     guards against **stale** timer messages: when a key is flushed early (for
     example by a size-triggered flush), its old timer may already have been
     superseded, and such messages carry an outdated ref and must be ignored.
   - If the matching entry has buffered events (`count > 0`), flush that key with
     `flush_key/3` (which delivers the batch in push order, cancels the key's
     timer, and drops the key so it starts fresh).
   - If the matching entry's buffer is empty, do **not** call the callback.
     Instead clear the key's timer with `clear_timer/1` and store the updated
     entry back with `put_entry/3`, so no empty flush occurs.
   - If there is no entry for `key`, or its `timer_ref` does not match `ref`,
     leave the state unchanged.
2. Ignore any other, unrelated info message, leaving the state unchanged.

In every case return `{:noreply, state}` with the (possibly updated) state.

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

  def handle_info({:flush, key, ref}, state) do
    # TODO
  end

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