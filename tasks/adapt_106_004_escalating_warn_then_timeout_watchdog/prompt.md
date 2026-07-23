# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

# Escalating (Warn-then-Timeout) Watchdog Timer GenServer

Write me an Elixir GenServer module called `EscalatingWatchdog` that monitors the
liveness of registered processes using a heartbeat mechanism with **two escalation
stages**. Each registration has an early `warn_ms` deadline and a later `timeout_ms`
deadline: if an entity goes quiet, the watchdog first fires a *warning* callback, and
only if it stays quiet longer does it fire the *timeout* callback and give up.

## Public API

- `EscalatingWatchdog.start_link(opts)` — starts the process.
  - Accepts a `:name` option for process registration. If not provided, the server
    registers itself under the name `EscalatingWatchdog` (i.e. `__MODULE__`), because all
    other API functions target that fixed registered name and take no server argument.
  - Returns `{:ok, pid}` (standard `GenServer.start_link/3` return).

- `EscalatingWatchdog.register(name, pid, warn_ms, timeout_ms, on_warn_fn, on_timeout_fn)`
  — begins monitoring an entity identified by `name` (any term).
  - `pid` is the process associated with this registration; record it, but the watchdog
    is **not** required to monitor the pid for `:DOWN`/exit events — liveness is
    determined purely by heartbeats.
  - `warn_ms` and `timeout_ms` are millisecond deadlines measured from the last
    heartbeat (or from registration). `warn_ms` **must be strictly less than**
    `timeout_ms`; otherwise the call raises `ArgumentError`.
  - `on_warn_fn` and `on_timeout_fn` are each **one-argument** functions, invoked as
    `on_warn_fn.(name)` and `on_timeout_fn.(name)` respectively.
  - The clock starts immediately. With no heartbeat, `on_warn_fn.(name)` fires at
    `warn_ms` (once), and `on_timeout_fn.(name)` fires at `timeout_ms`, after which the
    registration is removed.
  - Registering a `name` that is already registered **replaces** the previous
    registration entirely (new pid, deadlines, callbacks, phase reset, and freshly armed
    timers).
  - Returns `:ok`, synchronously — once it returns, both timers are armed.

- `EscalatingWatchdog.heartbeat(name)` — records a heartbeat for `name`, resetting **both**
  deadlines (a fresh `warn_ms` and `timeout_ms`) and returning the phase to `:healthy`.
  A heartbeat after a warning re-arms everything, so the warning can fire again later.
  - Calling `heartbeat/1` for an unregistered `name` is a harmless no-op.
  - Returns `:ok`, synchronously.

- `EscalatingWatchdog.phase(name)` — returns `{:ok, :healthy}` before the warning has
  fired, `{:ok, :warned}` after the warning has fired but before the timeout, or
  `{:error, :not_registered}` for an unknown name (including after a timeout has removed
  the registration).

- `EscalatingWatchdog.unregister(name)` — stops monitoring `name`. After this returns,
  neither the warning nor the timeout callback may fire for that `name`. Unregistering an
  unknown `name` is a no-op. Returns `:ok`.

## Escalation semantics

- Within a single silent window, `on_warn_fn.(name)` fires **at most once** (at
  `warn_ms`) and `on_timeout_fn.(name)` fires **at most once** (at `timeout_ms`), after
  which the registration is removed.
- A heartbeat resets the escalation: a heartbeat before `warn_ms` prevents the warning
  in that window; a heartbeat after the warning but before the timeout cancels the
  pending timeout and re-arms a fresh warn/timeout pair (so the warning can recur).
- Each registration is independent: escalation for one `name` must have no effect on any
  other `name`.

## Implementation notes

- Use `Process.send_after/3` (or `:timer`) to schedule the warn and timeout deadlines,
  and guard against stale timers (e.g. by tagging each armed generation with a reference)
  so a reset or unregister cannot let an old timer fire.
- Give me the complete module in a single file. Use only the OTP standard library,
  no external dependencies.
