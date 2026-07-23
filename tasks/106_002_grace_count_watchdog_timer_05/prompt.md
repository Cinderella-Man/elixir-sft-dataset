# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `start_link`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

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

## The module with `start_link` missing

```elixir
defmodule GraceWatchdog do
  @moduledoc """
  A GenServer that monitors liveness via heartbeats but tolerates a configurable
  number of consecutive missed intervals before firing.

  Each registered entity is expected to periodically call `heartbeat/1`. Every
  `interval_ms` that elapses without a heartbeat records a *miss* and re-arms a
  fresh timer. Only once `max_misses` consecutive misses accumulate does the
  watchdog invoke `on_timeout_fn.(name, miss_count)` (exactly once) and remove the
  registration. Any heartbeat resets the miss counter to zero.

  Timers are tagged with a unique reference so stale timers (from a reset or an
  unregister) can never fire spuriously.
  """

  use GenServer

  ## Public API

  def start_link(opts \\ []) do
    # TODO
  end

  @doc """
  Registers a watchdog for `name`/`pid` that fires `on_timeout_fn` after `max_misses`
  consecutive missed heartbeats spaced `interval_ms` apart. Returns `:ok`.
  """
  @spec register(
          term(),
          pid(),
          non_neg_integer(),
          pos_integer(),
          (term(), pos_integer() -> any())
        ) ::
          :ok
  def register(name, pid, interval_ms, max_misses, on_timeout_fn)
      when is_integer(interval_ms) and interval_ms >= 0 and is_integer(max_misses) and
             max_misses >= 1 and is_function(on_timeout_fn, 2) do
    GenServer.call(__MODULE__, {:register, name, pid, interval_ms, max_misses, on_timeout_fn})
  end

  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @spec misses(term()) :: {:ok, non_neg_integer()} | {:error, :not_registered}
  def misses(name), do: GenServer.call(__MODULE__, {:misses, name})

  ## GenServer callbacks

  @impl true
  def init(_arg), do: {:ok, %{}}

  @impl true
  def handle_call({:register, name, pid, interval_ms, max_misses, fun}, _from, state) do
    state = cancel_entry(state, name)
    ref = make_ref()
    timer = Process.send_after(self(), {:tick, name, ref}, interval_ms)

    entry = %{
      pid: pid,
      interval_ms: interval_ms,
      max_misses: max_misses,
      fun: fun,
      misses: 0,
      ref: ref,
      timer: timer
    }

    {:reply, :ok, Map.put(state, name, entry)}
  end

  def handle_call({:heartbeat, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer)
        ref = make_ref()
        timer = Process.send_after(self(), {:tick, name, ref}, entry.interval_ms)
        {:reply, :ok, Map.put(state, name, %{entry | misses: 0, ref: ref, timer: timer})}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  def handle_call({:misses, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} -> {:reply, {:ok, entry.misses}, state}
      :error -> {:reply, {:error, :not_registered}, state}
    end
  end

  @impl true
  def handle_info({:tick, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        misses = entry.misses + 1

        if misses >= entry.max_misses do
          safe_invoke(entry.fun, name, misses)
          {:noreply, Map.delete(state, name)}
        else
          new_ref = make_ref()
          timer = Process.send_after(self(), {:tick, name, new_ref}, entry.interval_ms)
          {:noreply, Map.put(state, name, %{entry | misses: misses, ref: new_ref, timer: timer})}
        end

      _ ->
        # Stale timer (reset/unregistered/replaced) — ignore.
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp cancel_entry(state, name) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        _ = Process.cancel_timer(entry.timer)
        Map.delete(state, name)

      :error ->
        state
    end
  end

  defp safe_invoke(fun, name, misses) do
    fun.(name, misses)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```

Output only `start_link` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
