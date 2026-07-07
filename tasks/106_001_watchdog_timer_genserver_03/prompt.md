# Fill in the middle: `Watchdog.handle_call/3`

The `Watchdog` GenServer below is complete except for its `handle_call/3`
callback, whose three clauses have had their bodies replaced with `# TODO`.
Implement all three clauses so the server behaves exactly as described.

The state is a map of the form `%{name => entry}`, where each `entry` is a map
`%{pid, interval_ms, on_timeout_fn, ref, timer_ref}`. Timers are tagged with a
unique `ref` so that stale timers (from a reset, replacement, or unregister) can
be detected and ignored in `handle_info/2`. A helper `cancel_entry/2` is already
provided: given the state and a `name`, it cancels that entry's timer (if any)
and removes the entry, returning the updated state (a no-op for unknown names).

Implement `handle_call/3` so that:

- **`{:register, name, pid, interval_ms, on_timeout_fn}`** — first cancel any
  existing registration for `name` (using `cancel_entry/2`) so a re-registration
  fully replaces the old one. Then arm a fresh timer: create a new unique `ref`
  with `make_ref()`, schedule `Process.send_after(self(), {:timeout, name, ref},
  interval_ms)` and keep the returned `timer_ref`. Build the entry map
  (`pid`, `interval_ms`, `on_timeout_fn`, `ref`, `timer_ref`), store it in the
  state under `name`, and reply `:ok`. The clock starts immediately.

- **`{:heartbeat, name}`** — if `name` is currently registered, reset its timer:
  cancel the existing `timer_ref` with `Process.cancel_timer/1`, generate a new
  `ref`, schedule a new timeout for the entry's own `interval_ms`, update the
  entry's `ref` and `timer_ref`, store it back, and reply `:ok`. If `name` is not
  registered, reply `:ok` and leave the state unchanged (harmless no-op).

- **`{:unregister, name}`** — remove the registration for `name` using
  `cancel_entry/2` so no timeout callback can later fire for it, and reply `:ok`.
  Unregistering an unknown `name` is a no-op.

All three clauses are synchronous calls that reply `:ok`.

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

  def handle_call({:register, name, pid, interval_ms, on_timeout_fn}, _from, state) do
    # TODO
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