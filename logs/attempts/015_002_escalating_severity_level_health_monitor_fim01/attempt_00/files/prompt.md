# Fill in the middle: `HealthMonitor.run_check/2`

Below is the complete `HealthMonitor` module, a singleton `GenServer` that
supervises registered *probes*, tracking each probe's severity level
(`:ok`, `:warning`, or `:critical`) and firing an `on_change` callback whenever
a probe's level changes.

Every function is provided **except** the private helper `run_check/2`, whose
body has been replaced with `# TODO`. Implement `run_check/2`.

## What `run_check/2` must do

`run_check(name, probe)` performs exactly one check for the probe map `probe`
registered under `name`, returns the **updated probe map**, and is the shared
worker used by both the periodic `{:check, ...}` timer message and by
`probe_now/1` — so the two paths behave identically.

It must:

1. Remember the probe's current level (`probe.level`) as the *old level*.
2. Call `probe.check_func.()` **exactly once** and branch on its result:
   - On `:ok` — reset the consecutive-failure count to `0`, set the new level to
     `:ok`, and use a `reason` of `nil`.
   - On `{:error, reason}` — increment the consecutive-failure count by one, then
     compute the new level **solely** from the resulting count using the existing
     `level_for/3` helper (`:critical` when the count is `>= crit_after`,
     otherwise `:warning` when `>= warn_after`, otherwise `:ok`), keeping that
     failing check's `reason`.
3. If (and only if) the new level **differs** from the old level, invoke
   `probe.on_change.(name, old_level, new_level, reason)` **exactly once**. If the
   level is unchanged, do not call `on_change`.
4. Return the probe map updated with the new `fail_count` and `level` (all other
   fields unchanged).

`run_check/2` must not schedule timers, touch other probes, or read/write server
state beyond the single `probe` map it is given.

## The whole module

```elixir
defmodule HealthMonitor do
  @moduledoc """
  A singleton `GenServer` that supervises a set of registered *probes*.

  Each probe has a zero-arity check function that is invoked on a periodic
  interval. Rather than a simple up/down status, every probe tracks one of
  three **severity levels** — `:ok`, `:warning`, or `:critical` — driven by
  how many checks have failed in a row:

    * a successful check (`:ok`) resets the consecutive-failure count to `0`
      and the level to `:ok`;
    * a failing check (`{:error, reason}`) increments the count, and the new
      level becomes `:critical` when the count is `>= :crit_after`, otherwise
      `:warning` when the count is `>= :warn_after`, otherwise `:ok`.

  Whenever a probe's level changes, an optional four-arity `on_change`
  callback is invoked exactly once with `(name, old_level, new_level, reason)`.

  The process is registered under the module name `HealthMonitor`, so the
  convenience functions take no server argument. Only the OTP standard
  library is used.
  """

  use GenServer

  @typedoc "A probe severity level."
  @type level :: :ok | :warning | :critical

  @typedoc "The result returned by a probe's check function."
  @type check_result :: :ok | {:error, term()}

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts and links the monitor process.

  The process is registered under `HealthMonitor` unless a `:name` option is
  given. A freshly started server tracks zero probes.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers (or re-registers) a probe under `name`.

  `check_func` must be a zero-arity function returning `:ok` or
  `{:error, reason}`. `interval_ms` is a positive integer giving how often the
  check runs after registration (the first check happens one interval later).

  Options:

    * `:warn_after` — positive integer, defaults to `2`;
    * `:crit_after` — positive integer, defaults to `4`;
    * `:on_change` — four-arity callback, defaults to a no-op.

  Re-adding an existing `name` replaces its configuration and resets its level
  to `:ok` with a failure count of `0`; previously scheduled checks for that
  name never run again.
  """
  @spec add_probe(term(), (-> check_result()), pos_integer(), keyword()) :: :ok
  def add_probe(name, check_func, interval_ms, opts \\ [])
      when is_function(check_func, 0) and is_integer(interval_ms) and interval_ms > 0 do
    GenServer.call(__MODULE__, {:add_probe, name, check_func, interval_ms, opts})
  end

  @doc """
  Returns the current severity level for `name`, or `{:error, :not_found}`.
  """
  @spec level(term()) :: level() | {:error, :not_found}
  def level(name) do
    GenServer.call(__MODULE__, {:level, name})
  end

  @doc """
  Returns a map of `%{name => level}` for every registered probe.
  """
  @spec report() :: %{optional(term()) => level()}
  def report do
    GenServer.call(__MODULE__, :report)
  end

  @doc """
  Synchronously performs exactly one check for `name`, immediately.

  Performs the identical work of a scheduled tick (running the check function,
  updating the failure count and level, and firing `on_change` on a level
  change) without altering or rescheduling the periodic timer.

  Returns `{:ok, level}` or `{:error, :not_found}`.
  """
  @spec probe_now(term()) :: {:ok, level()} | {:error, :not_found}
  def probe_now(name) do
    GenServer.call(__MODULE__, {:probe_now, name})
  end

  @doc """
  Removes the probe registered under `name`.

  Returns `:ok` if the probe existed (its scheduled checks never run again), or
  `{:error, :not_found}` if no such probe was registered.
  """
  @spec remove_probe(term()) :: :ok | {:error, :not_found}
  def remove_probe(name) do
    GenServer.call(__MODULE__, {:remove_probe, name})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:add_probe, name, check_func, interval_ms, opts}, _from, state) do
    warn_after = Keyword.get(opts, :warn_after, 2)
    crit_after = Keyword.get(opts, :crit_after, 4)
    on_change = Keyword.get(opts, :on_change, fn _name, _old, _new, _reason -> :ok end)
    token = make_ref()

    probe = %{
      check_func: check_func,
      interval_ms: interval_ms,
      warn_after: warn_after,
      crit_after: crit_after,
      on_change: on_change,
      level: :ok,
      fail_count: 0,
      token: token
    }

    Process.send_after(self(), {:check, name, token}, interval_ms)
    {:reply, :ok, Map.put(state, name, probe)}
  end

  def handle_call({:level, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, probe} -> {:reply, probe.level, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:report, _from, state) do
    report = Map.new(state, fn {name, probe} -> {name, probe.level} end)
    {:reply, report, state}
  end

  def handle_call({:probe_now, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, probe} ->
        updated = run_check(name, probe)
        {:reply, {:ok, updated.level}, Map.put(state, name, updated)}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:remove_probe, name}, _from, state) do
    case Map.has_key?(state, name) do
      true -> {:reply, :ok, Map.delete(state, name)}
      false -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:check, name, token}, state) do
    case Map.fetch(state, name) do
      {:ok, %{token: ^token} = probe} ->
        updated = run_check(name, probe)
        Process.send_after(self(), {:check, name, token}, probe.interval_ms)
        {:noreply, Map.put(state, name, updated)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Internal helpers ──────────────────────────────────────────────────────

  defp run_check(name, probe) do
    # TODO
  end

  @spec level_for(non_neg_integer(), pos_integer(), pos_integer()) :: level()
  defp level_for(count, warn_after, crit_after) do
    cond do
      count >= crit_after -> :critical
      count >= warn_after -> :warning
      true -> :ok
    end
  end
end
```