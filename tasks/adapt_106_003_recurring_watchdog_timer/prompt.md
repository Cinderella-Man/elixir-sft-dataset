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

# Recurring Watchdog Timer GenServer

Write me an Elixir GenServer module called `RecurringWatchdog` that monitors the
liveness of registered processes using a heartbeat mechanism. Unlike a one-shot
watchdog that alerts once and forgets, this watchdog keeps **re-alerting every interval**
for as long as an entity remains silent — a nagging "still down" alarm — and only goes
quiet again when a heartbeat arrives or the entity is unregistered.

## Public API

- `RecurringWatchdog.start_link(opts)` — starts the process.
  - Accepts a `:name` option for process registration. If not provided, the server
    registers itself under the name `RecurringWatchdog` (i.e. `__MODULE__`), because all
    other API functions target that fixed registered name and take no server argument.
  - Returns `{:ok, pid}` (standard `GenServer.start_link/3` return).

- `RecurringWatchdog.register(name, pid, interval_ms, on_timeout_fn)` — begins monitoring
  an entity identified by `name` (any term).
  - `pid` is the process associated with this registration; record it, but the watchdog
    is **not** required to monitor the pid for `:DOWN`/exit events — liveness is
    determined purely by heartbeats.
  - `interval_ms` is the maximum time (in milliseconds) allowed between heartbeats.
  - `on_timeout_fn` is a **one-argument** function invoked as `on_timeout_fn.(name)`.
  - The clock starts immediately: if no heartbeat arrives within `interval_ms`, the
    callback fires.
  - **Recurring behaviour:** after firing, the registration is *not* removed. The
    watchdog re-arms another `interval_ms` timer and, if still no heartbeat arrives,
    fires the callback again — repeating indefinitely until a heartbeat or unregister.
  - Registering a `name` that is already registered **replaces** the previous
    registration entirely (new pid, interval, callback, health reset to healthy, and a
    freshly armed timer).
  - Returns `:ok`, synchronously — once it returns, the timer is armed.

- `RecurringWatchdog.heartbeat(name)` — records a heartbeat for `name`, resetting its
  timer (another full `interval_ms`) and returning its status to `:healthy`.
  - Calling `heartbeat/1` for an unregistered `name` is a harmless no-op.
  - Returns `:ok`, synchronously.

- `RecurringWatchdog.status(name)` — returns `{:ok, :healthy}` before the first missed
  interval, `{:ok, :alerting}` once at least one alert has fired without an intervening
  heartbeat, or `{:error, :not_registered}` for an unknown name.

- `RecurringWatchdog.unregister(name)` — stops monitoring `name`. After this returns, no
  further alerts may fire for that `name`. Unregistering an unknown `name` is a no-op.
  Returns `:ok`.

## Alerting semantics

- Alerts are **recurring**: while an entity is silent, the callback fires once per
  elapsed `interval_ms`, and each firing sets the status to `:alerting`.
- A heartbeat re-arms the clock and resets the status to `:healthy`; if heartbeats
  keep arriving within the interval, no alert ever fires.
- Each registration is independent: alerts, heartbeats, and unregisters for one `name`
  must have no effect on any other `name`.

## Implementation notes

- Use `Process.send_after/3` (or `:timer`) to schedule alerts, and guard against stale
  timers (e.g. by tagging each armed timer with a reference) so a reset or unregister
  cannot let an old timer fire.
- Give me the complete module in a single file. Use only the OTP standard library,
  no external dependencies.
