# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# Debouncer — a GenServer that coalesces rapid calls

Write me an Elixir module called `Debouncer`, implemented as a `GenServer`, that
debounces function calls on a per-key basis. This is the kind of thing you'd use
to coalesce a burst of rapid writes (autosave, search-as-you-type, config reloads)
into a single execution.

## Public API

- `Debouncer.start_link(opts)` — starts the process. `opts` is a keyword list.
  It should accept a `:name` option for process registration, defaulting to
  `Debouncer` (i.e. the module name) when not provided. Returns the usual
  `GenServer.on_start()` result: `{:ok, pid}` on success, and
  `{:error, {:already_started, pid}}` if a process is already registered under
  that name. The server starts with no pending keys.

- `Debouncer.call(key, delay_ms, func)` — schedules `func` (a zero-arity function)
  to run after `delay_ms` milliseconds. `key` can be any term. `func` is a
  zero-arity closure whose only significance to the debouncer is that it gets
  invoked. This function returns `:ok` and returns promptly (it must not block
  waiting for `func` to run, and it must not block waiting for the server to
  process the request either — it is fire-and-forget). It targets the default
  registered process (the one registered under the name `Debouncer`), regardless
  of what `:name` any other running instance was started with.

  `delay_ms` must be a non-negative integer and `func` must be a function of
  arity 0. Calls that violate this — a negative or non-integer `delay_ms`, or a
  function of any other arity — raise a `FunctionClauseError` at the call site
  rather than being sent to the server. `delay_ms` of `0` is legal and means
  "fire on the next scheduler pass" — the func still runs asynchronously, never
  inline in the caller.

## Debounce semantics

- **Coalescing.** If `call/3` is invoked again with the **same key** before the
  pending timer for that key fires, the timer is reset (restarted from the *new*
  call's `delay_ms`) and the newly supplied `func` **replaces** the previously
  pending one. When the burst finally settles (i.e. `delay_ms` elapses with no
  further calls for that key), **only the most recently supplied `func` for that
  key runs, and it runs exactly once.** The earlier funcs from that burst are
  never executed. There is no cap on how long a key can be held off: an endless
  stream of calls spaced under `delay_ms` apart keeps deferring the func
  indefinitely.

- **The delay is real, including under a race.** `func` must not run before
  `delay_ms` has elapsed since the most recent `call/3` for that key. This must
  hold even in the window where an old timer has already fired and its message is
  sitting in the server's mailbox when the new `call/3` arrives — cancelling a
  timer cannot recall a message that was already delivered. Such a stale
  expiry must be recognized and discarded: it must not run the old func, must not
  run the new func early, and must not clear the new pending entry. Only the
  expiry that corresponds to the *currently pending* schedule for a key is
  allowed to fire. (Tagging each scheduled expiry with a unique identity — e.g. a
  `make_ref/0` stored alongside the timer — is the straightforward way to do
  this.)

- **Each call's delay is its own.** The delay used for a key is whatever the most
  recent `call/3` supplied. Calling `call(:k, 500, f1)` then, 10ms later,
  `call(:k, 20, f2)` means `f2` runs roughly 20ms after the second call, not 500ms
  after the first.

- **Keys are independent.** A pending debounce on one key must have no effect on
  any other key. Calls for different keys each get their own independent timer and
  each fire on their own schedule, in whatever order their delays dictate — a
  short-delay key fires before a long-delay key that was scheduled earlier. Keys
  are compared by term equality, so `:a`, `"a"`, and `{:a, 1}` are three distinct
  keys.

- **State is cleared after firing.** Once a key's `func` has executed, that key's
  pending state is removed from the server. A subsequent `call/3` for the same key
  (after the previous one already fired) starts a brand-new debounce cycle and
  will execute again — the debouncer keeps no memory of keys that have already
  fired, and there is no dedup across cycles. There is no way to observe or cancel
  a pending key through the public API; the only way state leaves the server is by
  firing.

- **A misbehaving `func` is contained.** Because the funcs are arbitrary caller
  code, a `func` that raises, exits, or blocks for a long time must not crash the
  GenServer, must not delay other keys' timers, and must not prevent subsequent
  `call/3`s from being accepted and honored. The server's own pending state for
  that key is cleared when the func is dispatched, regardless of whether the func
  ultimately succeeds. Two funcs whose executions overlap in time (e.g. a slow
  func for key `:a` still running when key `:b` fires) run concurrently rather
  than serially.

## Implementation notes

- Use `Process.send_after/3` for the timers and cancel/replace them
  (`Process.cancel_timer/1`) when a key is called again while pending. Remember
  that cancellation is best-effort — see the stale-expiry rule above.
- Run `func` outside the server's own reduction path (e.g. in a spawned process)
  so a slow or crashing `func` can't wedge the GenServer. The server does not link
  to, monitor, or await the func's execution, and does not report its result
  anywhere.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.

## The buggy module

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
    {:error, state}
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

## Failing test report

```
11 of 11 test(s) failed:

  * test coalesces rapid calls on the same key — only the last func runs
      failed to start child with the spec Debouncer.
      Reason: %{}

  * test executes the surviving func exactly once
      failed to start child with the spec Debouncer.
      Reason: %{}

  * test does not execute before the delay elapses
      failed to start child with the spec Debouncer.
      Reason: %{}

  * test each call resets the timer
      failed to start child with the spec Debouncer.
      Reason: %{}

  (…7 more)
```
