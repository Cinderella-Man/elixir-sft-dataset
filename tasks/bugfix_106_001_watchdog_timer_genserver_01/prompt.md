# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Watchdog Timer GenServer

Write me an Elixir GenServer module called `Watchdog` that monitors the liveness of
registered processes using a heartbeat mechanism. Each monitored entity is expected
to periodically "check in". If it fails to check in within its configured interval,
the `Watchdog` invokes a user-supplied timeout callback.

## Public API

- `Watchdog.start_link(opts)` — starts the process.
  - Accepts a `:name` option for process registration. If not provided, the server
    must register itself under the name `Watchdog` (i.e. `__MODULE__`), because all
    other API functions target that fixed registered name and take no server argument.
  - Returns `{:ok, pid}` (standard `GenServer.start_link/3` return).

- `Watchdog.register(name, pid, interval_ms, on_timeout_fn)` — begins monitoring an
  entity identified by `name` (any term).
  - `pid` is the process associated with this registration; record it (a correct
    callback may capture and use it), but the `Watchdog` is **not** required to monitor
    the pid for `:DOWN`/exit events — liveness is determined purely by heartbeats.
  - `interval_ms` is the maximum time (in milliseconds) allowed between heartbeats.
  - `on_timeout_fn` is a **one-argument** function. When a timeout fires the `Watchdog`
    must invoke it as `on_timeout_fn.(name)`.
  - Registering a `name` that is already registered **replaces** the previous
    registration entirely (new pid, interval, callback, and a freshly armed timer).
  - The clock starts immediately on registration: if no heartbeat arrives within
    `interval_ms` of registering, the timeout fires.
  - Returns `:ok`. This call must be synchronous — once it returns, the timer is armed.

- `Watchdog.heartbeat(name)` — records a heartbeat for `name`, resetting its timer so
  the entity has another full `interval_ms` before it is considered timed out.
  - Calling `heartbeat/1` for a `name` that is not currently registered is a harmless
    no-op.
  - Returns `:ok`. This call must be synchronous so that a heartbeat issued before a
    sleep is guaranteed to have reset the timer.

- `Watchdog.unregister(name)` — stops monitoring `name`. After this returns, no timeout
  callback may fire for that `name` (any already-scheduled timer must be effectively
  cancelled/ignored). Unregistering an unknown `name` is a no-op. Returns `:ok`.

## Timeout semantics

- A timeout is **one-shot**: when a registration times out, the `Watchdog` invokes
  `on_timeout_fn.(name)` exactly once and then removes the registration. It must not
  fire repeatedly for the same registration.
- Each registration is independent: a timeout (or heartbeat, or unregister) for one
  `name` must have no effect on any other `name`.
- A heartbeat that arrives after a registration has already timed out (and thus been
  removed) is treated as a heartbeat for an unknown name (no-op).

## Implementation notes

- Use `Process.send_after/3` (or `:timer`) to schedule timeouts, and guard against
  stale timers (e.g. by tagging each armed timer with a reference) so that a reset or
  unregister cannot let an old timer fire.
- Give me the complete module in a single file. Use only the OTP standard library,
  no external dependencies.

## The buggy module

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
    {:error, %{}}
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

## Failing test report

```
14 of 14 test(s) failed:

  * test does not fire while heartbeats arrive within the interval
      failed to start child with the spec {Watchdog, []}.
      Reason: %{}

  * test fires the callback when a heartbeat is missed
      failed to start child with the spec {Watchdog, []}.
      Reason: %{}

  * test callback receives the registered name
      failed to start child with the spec {Watchdog, []}.
      Reason: %{}

  * test heartbeat resets the timer so cumulative uptime exceeds the interval
      failed to start child with the spec {Watchdog, []}.
      Reason: %{}

  (…10 more)
```
