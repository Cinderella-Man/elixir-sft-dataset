# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_call` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `handle_call` missing

```elixir
defmodule EscalatingWatchdog do
  @moduledoc """
  A GenServer that monitors liveness via heartbeats with two escalation stages.

  Each registration has an early `warn_ms` deadline and a later `timeout_ms`
  deadline (measured from the last heartbeat or from registration). With no
  heartbeat, `on_warn_fn.(name)` fires once at `warn_ms` (moving the phase to
  `:warned`), and `on_timeout_fn.(name)` fires once at `timeout_ms`, after which the
  registration is removed. A heartbeat resets both deadlines and returns the phase to
  `:healthy`, so a heartbeat after a warning re-arms a fresh warn/timeout pair.

  Each generation of timers is tagged with a unique reference so stale timers (from a
  reset or an unregister) can never fire spuriously.
  """

  use GenServer

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Registers an escalating watchdog for `name`/`pid`: runs `on_warn_fn` after `warn_ms`
  of silence, then `on_timeout_fn` after `timeout_ms`. Returns `:ok`.
  """
  @spec register(
          term(),
          pid(),
          non_neg_integer(),
          non_neg_integer(),
          (term() -> any()),
          (term() -> any())
        ) :: :ok
  def register(name, pid, warn_ms, timeout_ms, on_warn_fn, on_timeout_fn)
      when is_integer(warn_ms) and warn_ms >= 0 and is_integer(timeout_ms) and
             is_function(on_warn_fn, 1) and is_function(on_timeout_fn, 1) do
    unless warn_ms < timeout_ms do
      raise ArgumentError, "warn_ms must be strictly less than timeout_ms"
    end

    GenServer.call(
      __MODULE__,
      {:register, name, pid, warn_ms, timeout_ms, on_warn_fn, on_timeout_fn}
    )
  end

  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @spec phase(term()) :: {:ok, :healthy | :warned} | {:error, :not_registered}
  def phase(name), do: GenServer.call(__MODULE__, {:phase, name})

  ## GenServer callbacks

  @impl true
  def init(_arg), do: {:ok, %{}}

  def handle_call(
        {:register, name, pid, warn_ms, timeout_ms, warn_fn, timeout_fn},
        _from,
        state
      ) do
    # TODO
  end

  @impl true
  def handle_info({:warn, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref, phase: :healthy} = entry} ->
        safe_invoke(entry.warn_fn, name)
        {:noreply, Map.put(state, name, %{entry | phase: :warned})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:timeout, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        safe_invoke(entry.timeout_fn, name)
        {:noreply, Map.delete(state, name)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp arm(entry, name) do
    ref = make_ref()
    warn_timer = Process.send_after(self(), {:warn, name, ref}, entry.warn_ms)
    timeout_timer = Process.send_after(self(), {:timeout, name, ref}, entry.timeout_ms)

    Map.merge(entry, %{
      ref: ref,
      phase: :healthy,
      warn_timer: warn_timer,
      timeout_timer: timeout_timer
    })
  end

  defp disarm(entry) do
    _ = Process.cancel_timer(entry.warn_timer)
    _ = Process.cancel_timer(entry.timeout_timer)
    entry
  end

  defp cancel_entry(state, name) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        disarm(entry)
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

Give me only the complete implementation of `handle_call` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
