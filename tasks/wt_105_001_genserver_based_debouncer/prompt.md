# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

# Debouncer — a GenServer that coalesces rapid calls

Write me an Elixir module called `Debouncer`, implemented as a `GenServer`, that
debounces function calls on a per-key basis. This is the kind of thing you'd use
to coalesce a burst of rapid writes (autosave, search-as-you-type, config reloads)
into a single execution.

## Public API

- `Debouncer.start_link(opts)` — starts the process. It should accept a `:name`
  option for process registration, defaulting to `Debouncer` (i.e. the module
  name) when not provided. Return the usual `{:ok, pid}`.

- `Debouncer.call(key, delay_ms, func)` — schedules `func` (a zero-arity function)
  to run after `delay_ms` milliseconds. `key` can be any term. `func` is a
  zero-arity closure whose only significance to the debouncer is that it gets
  invoked. This function should return `:ok` and return promptly (it must not
  block waiting for `func` to run). It targets the default registered process
  (the one registered under the name `Debouncer`).

## Debounce semantics

- **Coalescing.** If `call/3` is invoked again with the **same key** before the
  pending timer for that key fires, the timer is reset (restarted from
  `delay_ms`) and the newly supplied `func` **replaces** the previously pending
  one. When the burst finally settles (i.e. `delay_ms` elapses with no further
  calls for that key), **only the most recently supplied `func` for that key
  runs, and it runs exactly once.** The earlier funcs from that burst are never
  executed.

- **The delay is real.** `func` must not run before `delay_ms` has elapsed since
  the most recent `call/3` for that key.

- **Keys are independent.** A pending debounce on one key must have no effect on
  any other key. Calls for different keys each get their own independent timer
  and each fire on their own schedule.

- **State is cleared after firing.** Once a key's `func` has executed, that key's
  pending state is gone. A subsequent `call/3` for the same key (after the
  previous one already fired) starts a brand-new debounce cycle and will execute
  again.

## Implementation notes

- Use `Process.send_after/3` for the timers and cancel/replace them
  (`Process.cancel_timer/1`) when a key is called again while pending.
- Consider running `func` outside the server's own reduction path (e.g. in a
  spawned process) so a slow or crashing `func` can't wedge the GenServer, but
  this is your call as long as the observable semantics above hold.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.

## Module under test

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
  def call(key, delay_ms, func) when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) do
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
