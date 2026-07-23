# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule Debouncer do
  @moduledoc """
  A `GenServer` that debounces zero-arity function calls on a per-key basis.

  Rapid calls sharing the same key are coalesced: each new call for a key
  resets that key's timer and replaces the pending function, so only the most
  recently supplied function runs once the burst settles (after `delay_ms`
  elapses with no further calls for that key). Different keys are fully
  independent, each with their own timer and schedule.

  ## Example

      {:ok, _pid} = Debouncer.start_link([])

      # Only the last func runs, ~50ms after the final call.
      Debouncer.call(:save, 50, fn -> IO.puts("v1") end)
      Debouncer.call(:save, 50, fn -> IO.puts("v2") end)
      Debouncer.call(:save, 50, fn -> IO.puts("v3") end)
      #=> eventually prints "v3"
  """

  use GenServer

  @doc """
  Starts the debouncer process.

  Accepts a `:name` option for process registration, defaulting to `Debouncer`
  (the module name) when not provided.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Schedules `func` (a zero-arity function) to run after `delay_ms` milliseconds
  on the given `key`.

  If another `call/3` for the same `key` arrives before the pending timer fires,
  the timer is reset and `func` replaces the previously pending function, so only
  the most recent `func` for a burst runs (exactly once).

  Returns `:ok` promptly without blocking on `func`. Targets the process
  registered under the name `Debouncer`.
  """
  @spec call(term(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:debounce, key, delay_ms, func}, state) do
    # Cancel any pending timer for this key so the burst is coalesced. If the
    # old timer already fired, its message may be sitting in our queue —
    # cancellation cannot recall it, which is why every arm carries a unique
    # ref: handle_info/2 recognizes and drops the stale message.
    case Map.get(state, key) do
      {_ref, timer, _old_func} -> Process.cancel_timer(timer)
      nil -> :ok
    end

    ref = make_ref()
    timer = Process.send_after(self(), {:fire, key, ref}, delay_ms)
    {:noreply, Map.put(state, key, {ref, timer, func})}
  end

  @impl true
  def handle_info({:fire, key, ref}, state) do
    case Map.get(state, key) do
      {^ref, _timer, func} ->
        # Run the func off the server's reduction path so a slow or crashing
        # func can't wedge the GenServer.
        spawn(fn -> func.() end)
        {:noreply, Map.delete(state, key)}

      _ ->
        # Stale fire: the key was re-debounced (or already fired) after this
        # timer's message was queued, so its func was replaced. Dropping the
        # message keeps the replacement's delay real.
        {:noreply, state}
    end
  end
end
```

## New specification

# BatchDebouncer — a debouncer that accumulates items and flushes them as a batch

Write me an Elixir module called `BatchDebouncer`, implemented as a `GenServer`,
that debounces on a per-key basis but — instead of throwing away all-but-the-last
call — **accumulates the submitted items** during a burst and hands the whole
ordered batch to a handler when the burst settles. This is what you want for
"coalesce a flurry of small writes into one batched flush" (buffered log lines,
batched index updates, grouped notifications).

## Public API

- `BatchDebouncer.start_link(opts)` — starts the process. Accepts a `:name`
  option for registration, defaulting to `BatchDebouncer` when not provided.
  Returns `{:ok, pid}`.

- `BatchDebouncer.call(key, delay_ms, item, handler)` — records `item` (any
  term) under `key` and (re)arms the debounce timer for `delay_ms`. `handler` is
  a **1-arity** function that will eventually receive the list of accumulated
  items. A handler whose arity is not one is a caller error: `call/4` raises
  `FunctionClauseError` (guard it with `is_function(handler, 1)`). Returns `:ok`
  promptly and must not block on `handler`. Targets the default registered
  process.

- `BatchDebouncer.pending(key)` — returns the number of items currently buffered
  for `key` (0 if none). Useful for inspection/testing.

## Batch semantics

- **Accumulation, not replacement.** Each `call/4` for a key **appends** its
  `item` to that key's buffer and resets the timer from `delay_ms`. When the
  burst settles (i.e. `delay_ms` elapses with no further calls for that key), the
  handler is invoked **exactly once** with the list of all accumulated items **in
  submission order**. Items are never deduplicated — identical items each occupy
  their own slot in the batch.

- **Latest handler wins.** If different calls in the same burst supply different
  handlers, the handler from the **most recent** call is the one invoked (it
  still receives the full ordered batch).

- **The delay is real.** The handler must not run before `delay_ms` has elapsed
  since the most recent `call/4` for that key.

- **Keys are independent.** Each key accumulates and flushes its own batch on its
  own schedule; a burst on one key never mixes items into another.

- **State is cleared after flushing.** Once a key's batch has flushed, its buffer
  is gone and `pending/1` returns 0; a subsequent `call/4` starts a brand-new
  batch — including a `call/4` issued from inside a running handler.

## Implementation notes

- Use `Process.send_after/3` / `Process.cancel_timer/1` for timers, cancelling
  and re-arming on each call. A re-armed timer must flush exactly once — the
  replaced deadline must never produce a second flush.
- Run `handler` off the server's reduction path (e.g. `spawn`) so a slow or
  crashing handler can't wedge the GenServer. `pending/1` should be a synchronous
  call.
- Accumulate efficiently (e.g. prepend and reverse at flush time) — don't do
  O(n) appends per call.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.
