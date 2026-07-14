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

# EdgeDebouncer — a GenServer debouncer with leading / trailing / both edges

Write me an Elixir module called `EdgeDebouncer`, implemented as a `GenServer`,
that debounces function calls on a per-key basis with a configurable **firing
edge** — the classic trailing-edge debounce, a leading-edge debounce that fires
immediately, or **both** edges (fire on the way in *and* on the way out of a
burst). This mirrors the `leading`/`trailing` options you find in libraries like
lodash's `debounce`.

## Public API

- `EdgeDebouncer.start_link(opts)` — starts the process. It should accept a
  `:name` option for process registration, defaulting to `EdgeDebouncer` (the
  module name) when not provided. Return the usual `{:ok, pid}`.

- `EdgeDebouncer.call(key, delay_ms, func, opts \\ [])` — schedules/handles
  `func` (a zero-arity function) for `key`. `opts` accepts `:edge`, one of
  `:trailing` (default), `:leading`, or `:both`. `key` can be any term. This
  function must return `:ok` and return promptly (it must never block waiting for
  `func` to run). It targets the default registered process (registered under the
  name `EdgeDebouncer`). An invalid `:edge` value should raise `ArgumentError`.

## Edge semantics

A **burst** for a key begins with a `call/4` when that key has no pending timer,
and ends when `delay_ms` elapses with no further calls for that key. Within a
burst each new `call/4` resets the timer (restart from `delay_ms`) and replaces
the pending trailing `func`. The edge is determined by the **first** call that
opens the burst.

- **`:trailing`** — nothing runs on the way in; when the burst settles, only the
  most recently supplied `func` runs, exactly once. (Same behavior as a plain
  debouncer.)

- **`:leading`** — the first call's `func` runs **immediately**. All later calls
  in the burst are coalesced away and never run — no trailing execution occurs.

- **`:both`** — the first call's `func` runs immediately (leading). If — and only
  if — at least one *additional* call arrived during the burst, the most recently
  supplied `func` also runs once when the burst settles (trailing). A burst
  consisting of a single call fires leading only (never twice).

Other rules:

- **The delay is real.** Trailing executions must not run before `delay_ms` has
  elapsed since the most recent `call/4` for that key.
- **Keys are independent.** A pending debounce on one key must not affect another.
- **State is cleared after firing.** Once a burst settles, the key's state is
  gone; a subsequent `call/4` starts a brand-new burst (leading fires again).

## Implementation notes

- Use `Process.send_after/3` for the timers and cancel/replace them
  (`Process.cancel_timer/1`) when a key is called again while pending.
- Run `func` off the server's reduction path (e.g. in a spawned process) so a
  slow or crashing `func` can't wedge the GenServer.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.
