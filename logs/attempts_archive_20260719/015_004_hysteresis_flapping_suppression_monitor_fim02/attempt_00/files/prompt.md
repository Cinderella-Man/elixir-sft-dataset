# Fill in the middle: `handle_ok/2`

Implement the private `handle_ok/2` function of the `StabilityMonitor` module below.
It is called (via `run_check/2`) when a service's check function returns `:ok`, and it
returns the updated service map. Its job is to apply the "healthy result" half of the
hysteresis rules.

`handle_ok/2` receives the service `name` and its current `service` map (which carries
the confirmed `state`, the `ok_streak` and `fail_streak` counters, the `ok_confirm`
threshold, and the `on_transition` callback). It must:

- Always reset the failure streak (`fail_streak`) to `0`, since a success breaks any
  run of failures.
- If the confirmed `state` is currently `:down`, increment the success streak
  (`ok_streak`) by one. If the incremented streak **reaches** `ok_confirm`, the
  service recovers: transition the confirmed `state` to `:up`, invoke
  `on_transition.(name, :down, :up)` **exactly once**, and reset `ok_streak` to `0`
  (and `fail_streak` to `0`). Otherwise the service stays `:down` with the newly
  incremented `ok_streak` and `fail_streak` at `0`; no callback fires.
- If the confirmed `state` is currently `:up`, the service simply stays up: reset
  `ok_streak` to `0` (and `fail_streak` to `0`) and fire no callback.

The function returns the updated `service` map in every case.

```elixir
defmodule StabilityMonitor do
  @moduledoc """
  A singleton `GenServer` that supervises registered services by periodically
  calling a zero-arity check function for each one, and reports a *confirmed*
  `:up`/`:down` state that changes only after the service has been consistently
  failing (or consistently recovering) for a configured number of checks.

  This hysteresis suppresses "flapping": a service that alternates between success
  and failure never changes its confirmed state, because a result opposite to the
  current confirmed state resets the streak that was building toward a transition.

  Each service tracks:

    * a confirmed `state` (`:up` or `:down`), starting at `:up`;
    * a `fail_streak` counter of consecutive failures while `:up`;
    * an `ok_streak` counter of consecutive successes while `:down`.

  A confirmed transition invokes the service's `:on_transition` callback exactly
  once. Services are fully independent of one another.

  Only the OTP standard library is used.
  """

  use GenServer

  @default_fail_confirm 3
  @default_ok_confirm 2
  @noop_transition &StabilityMonitor.__noop_transition__/3

  @typedoc "Confirmed service state."
  @type confirmed_state :: :up | :down

  @typedoc "A zero-arity health check returning `:ok` or `{:error, reason}`."
  @type check_func :: (-> :ok | {:error, term()})

  @typedoc "Callback invoked on a confirmed transition."
  @type on_transition :: (term(), confirmed_state(), confirmed_state() -> any())

  ## Public API

  @doc """
  Starts and links the monitor process.

  The process is registered under the name `StabilityMonitor` (overridable with the
  `:name` option, though the convenience functions always target `StabilityMonitor`).
  A freshly started server tracks zero services.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers (or re-registers) a service to be watched.

  `name` is any term used as the key. `check_func` is a zero-arity function returning
  `:ok` or `{:error, reason}`. `interval_ms` is a positive integer giving the check
  period in milliseconds; the first check runs one interval after registration.

  Options:

    * `:fail_confirm` — positive integer, consecutive failures to confirm `:down`
      (default `3`);
    * `:ok_confirm` — positive integer, consecutive successes to confirm `:up`
      (default `2`);
    * `:on_transition` — three-arity `fun.(name, from, to)` fired on each confirmed
      transition (default no-op).

  Re-watching an existing `name` replaces its configuration and resets its confirmed
  state to `:up` with both streaks at `0`; any previously scheduled checks for it are
  discarded. Returns `:ok`.
  """
  @spec watch(term(), check_func(), pos_integer(), keyword()) :: :ok
  def watch(name, check_func, interval_ms, opts \\ [])
      when is_function(check_func, 0) and is_integer(interval_ms) and interval_ms > 0 do
    GenServer.call(__MODULE__, {:watch, name, check_func, interval_ms, opts})
  end

  @doc """
  Synchronously performs exactly one check for `name`, identical to a scheduled tick.

  Returns `{:ok, state}` with the resulting confirmed state, or `{:error, :not_found}`
  if the service is not registered. Does not alter or reschedule the periodic timer.
  """
  @spec force_check(term()) :: {:ok, confirmed_state()} | {:error, :not_found}
  def force_check(name) do
    GenServer.call(__MODULE__, {:force_check, name})
  end

  @doc """
  Returns the confirmed state (`:up` or `:down`) for `name`, or `{:error, :not_found}`
  if the service is unknown.
  """
  @spec state(term()) :: confirmed_state() | {:error, :not_found}
  def state(name) do
    GenServer.call(__MODULE__, {:state, name})
  end

  @doc """
  Returns a map of `%{name => state}` for every currently registered service.

  Returns `%{}` when no services are registered.
  """
  @spec states() :: %{optional(term()) => confirmed_state()}
  def states do
    GenServer.call(__MODULE__, :states)
  end

  @doc """
  Removes the service `name`.

  Returns `:ok` if it existed (its scheduled checks will never run again), or
  `{:error, :not_found}` if no such service was registered.
  """
  @spec unwatch(term()) :: :ok | {:error, :not_found}
  def unwatch(name) do
    GenServer.call(__MODULE__, {:unwatch, name})
  end

  @doc false
  @spec __noop_transition__(term(), confirmed_state(), confirmed_state()) :: :ok
  def __noop_transition__(_name, _from, _to), do: :ok

  ## GenServer callbacks

  @impl true
  @spec init(keyword()) :: {:ok, %{services: map()}}
  def init(_opts) do
    {:ok, %{services: %{}}}
  end

  @impl true
  def handle_call({:watch, name, check_func, interval_ms, opts}, _from, state) do
    service = %{
      check_func: check_func,
      interval_ms: interval_ms,
      fail_confirm: get_pos_int(opts, :fail_confirm, @default_fail_confirm),
      ok_confirm: get_pos_int(opts, :ok_confirm, @default_ok_confirm),
      on_transition: get_transition(opts),
      state: :up,
      fail_streak: 0,
      ok_streak: 0,
      generation: make_ref()
    }

    schedule_check(name, service.interval_ms, service.generation)
    services = Map.put(state.services, name, service)
    {:reply, :ok, %{state | services: services}}
  end

  def handle_call({:force_check, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        updated = run_check(name, service)
        services = Map.put(state.services, name, updated)
        {:reply, {:ok, updated.state}, %{state | services: services}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:state, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, service.state, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:states, _from, state) do
    reply = Map.new(state.services, fn {name, service} -> {name, service.state} end)
    {:reply, reply, state}
  end

  def handle_call({:unwatch, name}, _from, state) do
    case Map.pop(state.services, name) do
      {nil, _services} ->
        {:reply, {:error, :not_found}, state}

      {_service, services} ->
        {:reply, :ok, %{state | services: services}}
    end
  end

  @impl true
  def handle_info({:check, name, generation}, state) do
    case Map.fetch(state.services, name) do
      {:ok, %{generation: ^generation} = service} ->
        updated = run_check(name, service)
        schedule_check(name, updated.interval_ms, updated.generation)
        services = Map.put(state.services, name, updated)
        {:noreply, %{state | services: services}}

      _superseded_or_removed ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  @spec schedule_check(term(), pos_integer(), reference()) :: reference()
  defp schedule_check(name, interval_ms, generation) do
    Process.send_after(self(), {:check, name, generation}, interval_ms)
  end

  @spec run_check(term(), map()) :: map()
  defp run_check(name, service) do
    case service.check_func.() do
      :ok -> handle_ok(name, service)
      {:error, _reason} -> handle_error(name, service)
    end
  end

  defp handle_ok(name, %{state: :down} = service) do
    # TODO
  end

  @spec handle_error(term(), map()) :: map()
  defp handle_error(name, %{state: :up} = service) do
    fail_streak = service.fail_streak + 1

    if fail_streak >= service.fail_confirm do
      service.on_transition.(name, :up, :down)
      %{service | state: :down, fail_streak: 0, ok_streak: 0}
    else
      %{service | fail_streak: fail_streak, ok_streak: 0}
    end
  end

  defp handle_error(_name, %{state: :down} = service) do
    %{service | fail_streak: 0, ok_streak: 0}
  end

  @spec get_pos_int(keyword(), atom(), pos_integer()) :: pos_integer()
  defp get_pos_int(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> default
    end
  end

  @spec get_transition(keyword()) :: on_transition()
  defp get_transition(opts) do
    case Keyword.get(opts, :on_transition) do
      fun when is_function(fun, 3) -> fun
      _other -> @noop_transition
    end
  end
end
```