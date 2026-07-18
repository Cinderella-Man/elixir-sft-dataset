# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

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
  `func`. Targets the default registered process. `delay_ms` is a non-negative
  integer (`0` is allowed) and `max_ms >= delay_ms` is required; a call with
  `max_ms < delay_ms` must raise `FunctionClauseError`.

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

## The buggy module

```elixir
defmodule MaxWaitDebouncer do
  @moduledoc """
  A `GenServer` debouncer with a maximum-wait guarantee and manual flush/cancel.

  Like a normal debouncer it coalesces rapid same-key calls (resetting the timer
  and replacing the pending func), but it also guarantees the pending func fires
  no later than `max_ms` after the burst's first call — so a sustained burst
  can't starve execution forever. `flush/1` runs the pending func immediately;
  `cancel/1` drops it.
  """

  use GenServer

  @doc """
  Starts the debouncer. Accepts a `:name` option, defaulting to `MaxWaitDebouncer`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Schedules `func` for `key`, coalescing with `delay_ms` but guaranteeing a fire
  within `max_ms` of the burst's first call. Returns `:ok` promptly.
  """
  @spec call(term(), non_neg_integer(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, max_ms, func)
      when is_integer(delay_ms) and delay_ms > 0 and is_integer(max_ms) and
             max_ms >= delay_ms and
             is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, max_ms, func})
  end

  @doc "Immediately runs the pending func for `key` (if any) and clears state."
  @spec flush(term()) :: :ok
  def flush(key), do: GenServer.call(__MODULE__, {:flush, key})

  @doc "Discards the pending func for `key` without running it."
  @spec cancel(term()) :: :ok
  def cancel(key), do: GenServer.call(__MODULE__, {:cancel, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, max_ms, func}, state) do
    now = mono_ms()

    first_at =
      case Map.get(state, key) do
        %{timer: ref, first_at: at} ->
          Process.cancel_timer(ref)
          at

        nil ->
          now
      end

    remaining_until_max = max(0, first_at + max_ms - now)
    fire_in = max(0, min(delay_ms, remaining_until_max))
    ref = Process.send_after(self(), {:fire, key}, fire_in)

    entry = %{timer: ref, func: func, first_at: first_at}
    {:noreply, Map.put(state, key, entry)}
  end

  @impl true
  def handle_call({:flush, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref, func: func}, new_state} ->
        Process.cancel_timer(ref)
        run(func)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:cancel, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref}, new_state} ->
        Process.cancel_timer(ref)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {%{func: func}, new_state} ->
        run(func)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end

  defp run(func), do: spawn(fn -> func.() end)

  defp mono_ms, do: System.monotonic_time(:millisecond)
end
```

## Failing test report

```
1 of 12 test(s) failed:

  * test accepts a zero delay and fires promptly
      no function clause matching in MaxWaitDebouncer.call/4
```
