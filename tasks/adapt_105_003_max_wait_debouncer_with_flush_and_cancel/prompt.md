# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

# MaxWaitDebouncer — a debouncer with a guaranteed max wait, plus flush/cancel

Write me an Elixir module called `MaxWaitDebouncer`, implemented as a
`GenServer`, that debounces zero-arity function calls on a per-key basis but adds
a **maximum wait** guarantee and manual **flush**/**cancel** controls. A plain
debouncer can starve forever during a sustained burst (the timer keeps resetting
and the func never runs); the max-wait bound guarantees the func runs at least
once per `max_ms`, which is what you want for things like autosave. This mirrors
lodash's `maxWait` option.

## Public API

- `MaxWaitDebouncer.start_link(opts)` — starts the process. Accepts a `:name`
  option for registration, defaulting to `MaxWaitDebouncer` when not provided.
  Returns `{:ok, pid}`.

- `MaxWaitDebouncer.call(key, delay_ms, max_ms, func)` — schedules `func` (a
  zero-arity closure) for `key`. Returns `:ok` promptly and must not block on
  `func`. Targets the default registered process. Requires `max_ms >= delay_ms`.

- `MaxWaitDebouncer.flush(key)` — if a func is pending for `key`, run it
  immediately and clear the key's state. Returns `:ok` (also `:ok` when nothing
  is pending).

- `MaxWaitDebouncer.cancel(key)` — discard any pending func for `key` without
  running it, cancelling its timer. Returns `:ok`.

## Semantics

- **Coalescing.** As with a normal debouncer, calling again with the same key
  before its timer fires resets the timer (from `delay_ms`) and replaces the
  pending `func`. Only one func ultimately runs per burst.

- **Max wait.** Track when the current burst's **first** call happened. The func
  must fire no later than `first_call_at + max_ms`, even if calls keep arriving
  fast enough that the `delay_ms` timer would otherwise keep resetting. Concretely,
  each call schedules the next fire at `min(delay_ms, remaining_until_max)` where
  `remaining_until_max = first_call_at + max_ms - now` (never negative). The func
  that runs is the most recently supplied one at fire time.

- **State cleared after firing.** After any fire (by delay, by max-wait, or by
  `flush/1`), the key's state is gone and the next `call/4` starts a fresh burst
  with a new max-wait window.

- **Keys are independent.** Each key has its own timer, burst-start time, and
  pending func.

## Implementation notes

- Use `Process.send_after/3` / `Process.cancel_timer/1` for timers, and
  `System.monotonic_time(:millisecond)` for elapsed-time math.
- Run `func` off the server's reduction path (e.g. `spawn`) so a slow or crashing
  func can't wedge the GenServer. `flush/1` and `cancel/1` should be synchronous
  calls that reply `:ok`.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.
