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
defmodule Watchdog do
  @moduledoc """
  A GenServer that monitors the liveness of registered entities via a heartbeat
  mechanism.

  Each registered entity is expected to periodically "check in" by calling
  `heartbeat/1`. If an entity fails to check in within its configured
  `interval_ms`, the `Watchdog` invokes the user-supplied timeout callback
  exactly once (as `on_timeout_fn.(name)`) and removes the registration.

  Liveness is determined purely by heartbeats — the associated `pid` is recorded
  but is not monitored for `:DOWN`/exit events.

  Timers are tagged with a unique reference so that stale timers (from a reset or
  an unregister) can never fire a spurious timeout.
  """

  use GenServer

  ## Public API

  @doc """
  Starts the `Watchdog` server.

  Accepts a `:name` option for process registration. If not provided the server
  registers itself under `#{inspect(__MODULE__)}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Begins monitoring `name`. Replaces any existing registration for `name`.

  The clock starts immediately: if no heartbeat arrives within `interval_ms`,
  `on_timeout_fn.(name)` is invoked. Synchronous — once it returns, the timer is
  armed.
  """
  @spec register(term(), pid(), non_neg_integer(), (term() -> any())) :: :ok
  def register(name, pid, interval_ms, on_timeout_fn)
      when is_integer(interval_ms) and interval_ms >= 0 and is_function(on_timeout_fn, 1) do
    GenServer.call(__MODULE__, {:register, name, pid, interval_ms, on_timeout_fn})
  end

  @doc """
  Records a heartbeat for `name`, resetting its timer. No-op for unknown names.
  Synchronous.
  """
  @spec heartbeat(term()) :: :ok
  def heartbeat(name) do
    GenServer.call(__MODULE__, {:heartbeat, name})
  end

  @doc """
  Stops monitoring `name`. After returning, no timeout callback fires for `name`.
  No-op for unknown names.
  """
  @spec unregister(term()) :: :ok
  def unregister(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end

  ## GenServer callbacks

  @impl true
  def init(_arg) do
    # State: %{name => %{pid, interval_ms, on_timeout_fn, ref, timer_ref}}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, name, pid, interval_ms, on_timeout_fn}, _from, state) do
    state = cancel_entry(state, name)

    ref = make_ref()
    timer_ref = Process.send_after(self(), {:timeout, name, ref}, interval_ms)

    entry = %{
      pid: pid,
      interval_ms: interval_ms,
      on_timeout_fn: on_timeout_fn,
      ref: ref,
      timer_ref: timer_ref
    }

    {:reply, :ok, Map.put(state, name, entry)}
  end

  @impl true
  def handle_call({:heartbeat, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer_ref)
        ref = make_ref()
        timer_ref = Process.send_after(self(), {:timeout, name, ref}, entry.interval_ms)
        entry = %{entry | ref: ref, timer_ref: timer_ref}
        {:reply, :ok, Map.put(state, name, entry)}

      :error ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  @impl true
  def handle_info({:timeout, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        # Valid, current timer fired: invoke callback once and remove.
        safe_invoke(entry.on_timeout_fn, name)
        {:noreply, Map.delete(state, name)}

      _ ->
        # Stale timer (reset/unregistered/replaced) — ignore.
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp cancel_entry(state, name) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer_ref)
        Map.delete(state, name)

      :error ->
        state
    end
  end

  defp safe_invoke(fun, name) do
    fun.(name)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```

## New specification

# Grace-Count Watchdog Timer GenServer

Write me an Elixir GenServer module called `GraceWatchdog` that monitors the liveness
of registered processes using a heartbeat mechanism, but which tolerates a configurable
number of *consecutive missed intervals* before it declares an entity dead. Unlike a
plain watchdog that fires on the first missed heartbeat, this one only invokes the
timeout callback after the entity has missed its check-in `max_misses` times in a row.

## Public API

- `GraceWatchdog.start_link(opts)` — starts the process.
  - Accepts a `:name` option for process registration. If not provided, the server
    registers itself under the name `GraceWatchdog` (i.e. `__MODULE__`), because all
    other API functions target that fixed registered name and take no server argument.
  - Returns `{:ok, pid}` (standard `GenServer.start_link/3` return).

- `GraceWatchdog.register(name, pid, interval_ms, max_misses, on_timeout_fn)` — begins
  monitoring an entity identified by `name` (any term).
  - `pid` is the process associated with this registration; record it, but the watchdog
    is **not** required to monitor the pid for `:DOWN`/exit events — liveness is
    determined purely by heartbeats.
  - `interval_ms` is the maximum time (in milliseconds) allowed between heartbeats
    before a *miss* is recorded.
  - `max_misses` is a positive integer: the number of consecutive missed intervals that
    must elapse before the timeout callback fires.
  - `on_timeout_fn` is a **two-argument** function. When the miss threshold is reached
    the watchdog invokes it as `on_timeout_fn.(name, miss_count)` where `miss_count`
    equals `max_misses`.
  - The clock starts immediately: the first miss is recorded `interval_ms` after
    registration if no heartbeat has arrived.
  - Each elapsed interval with no heartbeat increments the miss counter and re-arms a
    fresh timer for another `interval_ms`. Only when the counter reaches `max_misses`
    is the callback invoked and the registration removed.
  - Registering a `name` that is already registered **replaces** the previous
    registration entirely (new pid, interval, threshold, callback, a reset miss count,
    and a freshly armed timer).
  - Returns `:ok`. This call must be synchronous — once it returns, the timer is armed.

- `GraceWatchdog.heartbeat(name)` — records a heartbeat for `name`, resetting its miss
  counter to `0` and re-arming its timer so the entity has another full `interval_ms`
  before the next miss.
  - Calling `heartbeat/1` for an unregistered `name` is a harmless no-op.
  - Returns `:ok`, synchronously.

- `GraceWatchdog.misses(name)` — returns `{:ok, current_miss_count}` for a registered
  `name`, or `{:error, :not_registered}` otherwise.

- `GraceWatchdog.unregister(name)` — stops monitoring `name`. After this returns, no
  timeout callback may fire for that `name`. Unregistering an unknown `name` is a no-op.
  Returns `:ok`.

## Timeout semantics

- The timeout is **one-shot**: once the miss threshold is reached, the watchdog invokes
  `on_timeout_fn.(name, max_misses)` exactly once and removes the registration.
- A single heartbeat resets the miss count to zero — a burst of misses that stops short
  of the threshold and is then interrupted by a heartbeat must never fire.
- Each registration is independent: misses, heartbeats, and unregisters for one `name`
  must have no effect on any other `name`.

## Implementation notes

- Use `Process.send_after/3` (or `:timer`) to schedule ticks, and guard against stale
  timers (e.g. by tagging each armed timer with a reference) so a reset or unregister
  cannot let an old timer increment the counter or fire.
- Give me the complete module in a single file. Use only the OTP standard library,
  no external dependencies.
