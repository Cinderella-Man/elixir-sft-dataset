# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `unregister` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `IntervalScheduler` that accepts job registrations with simple interval schedules (every N seconds/minutes/hours/days) and executes them at drift-free intervals.

I need these functions in the public API:

- `IntervalScheduler.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime` representing the current time. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) that controls how frequently the GenServer checks for due jobs via `Process.send_after(self(), :tick, tick_interval_ms)`. Setting it to `:infinity` disables automatic ticking entirely (useful for testing).

- `IntervalScheduler.register(server, name, interval_spec, {mod, fun, args})` which registers a named job. `name` is a string or atom identifier that must be unique. `interval_spec` is a tuple of the form `{:every, n, unit}` where `n` is a positive integer and `unit` is one of `:seconds`, `:minutes`, `:hours`, `:days`. Return `:ok` on success. Return `{:error, :invalid_interval}` if the spec doesn't match this shape or the integer is non-positive. Return `{:error, :already_exists}` if a job with that name is already registered. Upon registration, record the current clock value as the job's `started_at` anchor and compute its initial `next_run`.

- `IntervalScheduler.unregister(server, name)` which removes a registered job. Return `:ok` if the job was found and removed. Return `{:error, :not_found}` if no job with that name exists.

- `IntervalScheduler.jobs(server)` which returns a list of `{name, interval_spec, next_run}` tuples for all registered jobs, where `next_run` is a `NaiveDateTime`.

- `IntervalScheduler.next_run(server, name)` which returns `{:ok, next_run_datetime}` for a registered job or `{:error, :not_found}` if the job doesn't exist.

The scheduling algorithm must be **drift-free**: the next_run for a job is always computed relative to the job's `started_at`, never relative to the actual execution time. Specifically, `next_run = started_at + N * interval_seconds` for the smallest integer N ≥ 1 such that the result is strictly greater than the current clock time. This has two important consequences:

- A tick that arrives slightly late does NOT push future scheduled times later. If started_at = T0, interval = 60s, and a tick arrives at T0 + 61s (one second late), the execution happens and the new next_run is T0 + 120s, not T0 + 121s. This prevents cumulative drift over long-running jobs.

- **Missed-interval catch-up is disabled.** If the scheduler was down (or the clock jumped forward) such that multiple interval boundaries were crossed without execution, each missed boundary is **skipped**, not replayed. If started_at = T0, interval = 60s, and a tick arrives at T0 + 250s, the job executes exactly once at T0 + 250s and its next_run is set to T0 + 300s (the next boundary > now) — NOT four separate catch-up executions for the missed boundaries at T0 + 60s, T0 + 120s, T0 + 180s, T0 + 240s.

On each `:tick` message, the GenServer should read the current time from the clock function, find all jobs whose `next_run` is less than or equal to the current time, execute each one by calling `apply(mod, fun, args)`, and then recalculate their next run time using the drift-free formula above. Multiple jobs that are due at the same tick must all execute. A job function that raises or throws must not crash the scheduler — wrap the `apply/3` call in a try/rescue/catch. After processing, if `tick_interval_ms` is not `:infinity`, schedule the next tick with `Process.send_after`.

Store the job data as a map or struct keyed by name, tracking at least the mfa tuple, the interval_spec, the `started_at` datetime, and the current `next_run` datetime.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `unregister` missing

```elixir
defmodule IntervalScheduler do
  @moduledoc """
  A GenServer that executes jobs on drift-free fixed intervals.

  Jobs are registered with a simple spec `{:every, n, unit}` where `unit` is
  `:seconds | :minutes | :hours | :days`.  Each job carries an immutable
  `started_at` anchor (captured from the injected clock at registration time);
  its `next_run` is always computed relative to that anchor using:

      next_run = started_at + N * interval_seconds

  for the smallest `N >= 1` such that `next_run > now`.  This guarantees two
  properties the naive `next = now + interval` approach fails:

    1. **No cumulative drift** — a tick that arrives slightly late does not
       push future runs further out.
    2. **No catch-up replay** — if many interval boundaries were missed (e.g.
       the scheduler was down), each missed boundary is skipped, not replayed.

  ## Options

    * `:name`              – process registration name (optional)
    * `:clock`             – zero-arity function returning a `NaiveDateTime`
                             (default: `fn -> NaiveDateTime.utc_now() end`)
    * `:tick_interval_ms`  – how often to check for due jobs; pass `:infinity`
                             to disable auto-ticking for tests (default `1_000`)

  ## Examples

      iex> {:ok, pid} = IntervalScheduler.start_link([])
      iex> mfa = {IO, :puts, ["tick"]}
      iex> :ok = IntervalScheduler.register(pid, "heartbeat", {:every, 30, :seconds}, mfa)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec register(GenServer.server(), term(), tuple(), {module(), atom(), list()}) ::
          :ok | {:error, :invalid_interval | :already_exists}
  @doc """
  Registers a recurring `job_name` that runs `mfa` on `interval_spec`. Returns `:ok`,
  or `{:error, :invalid_interval | :already_exists}`.
  """
  def register(server, job_name, interval_spec, {mod, fun, args} = mfa)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, job_name, interval_spec, mfa})
  end

  def unregister(server, job_name) do
    # TODO
  end

  @spec jobs(GenServer.server()) :: [{term(), tuple(), NaiveDateTime.t()}]
  def jobs(server), do: GenServer.call(server, :jobs)

  @spec next_run(GenServer.server(), term()) :: {:ok, NaiveDateTime.t()} | {:error, :not_found}
  def next_run(server, job_name), do: GenServer.call(server, {:next_run, job_name})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> NaiveDateTime.utc_now() end)
    tick_interval = Keyword.get(opts, :tick_interval_ms, 1_000)

    schedule_tick(tick_interval)

    {:ok,
     %{
       jobs: %{},
       clock: clock,
       tick_interval_ms: tick_interval
     }}
  end

  @impl true
  def handle_call({:register, name, spec, mfa}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        case parse_interval(spec) do
          {:ok, interval_s} ->
            now = state.clock.()

            job = %{
              mfa: mfa,
              interval_spec: spec,
              interval_s: interval_s,
              started_at: now,
              next_run: compute_next_run(now, interval_s, now)
            }

            {:reply, :ok, %{state | jobs: Map.put(state.jobs, name, job)}}

          :error ->
            {:reply, {:error, :invalid_interval}, state}
        end
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.pop(state.jobs, name) do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_, new_jobs} -> {:reply, :ok, %{state | jobs: new_jobs}}
    end
  end

  def handle_call(:jobs, _from, state) do
    list =
      Enum.map(state.jobs, fn {name, job} ->
        {name, job.interval_spec, job.next_run}
      end)

    {:reply, list, state}
  end

  def handle_call({:next_run, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, job} -> {:reply, {:ok, job.next_run}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    now = state.clock.()

    new_jobs =
      Enum.reduce(state.jobs, %{}, fn {name, job}, acc ->
        if NaiveDateTime.compare(job.next_run, now) != :gt do
          # Due — execute and reschedule from `now` (drift-free, no catch-up).
          _ = safe_execute(job.mfa)
          updated = %{job | next_run: compute_next_run(job.started_at, job.interval_s, now)}
          Map.put(acc, name, updated)
        else
          Map.put(acc, name, job)
        end
      end)

    schedule_tick(state.tick_interval_ms)
    {:noreply, %{state | jobs: new_jobs}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Core scheduling math — the whole point of this module
  # ---------------------------------------------------------------------------

  # Drift-free: next_run = started_at + N*interval_s for smallest N>=1 such
  # that result > now.  Equivalently:
  #
  #   elapsed = now - started_at
  #   N = max(1, div(elapsed, interval_s) + 1)
  #
  # Examples with started_at=0, interval=10:
  #   now=0   -> elapsed=0,  N=max(1, 0+1)=1, next=10   (first run)
  #   now=9   -> elapsed=9,  N=max(1, 0+1)=1, next=10
  #   now=10  -> elapsed=10, N=max(1, 1+1)=2, next=20   (boundary just hit)
  #   now=25  -> elapsed=25, N=max(1, 2+1)=3, next=30   (no catch-up replay)
  defp compute_next_run(started_at, interval_s, now) do
    elapsed = NaiveDateTime.diff(now, started_at, :second)
    n = max(1, div(elapsed, interval_s) + 1)
    NaiveDateTime.add(started_at, n * interval_s, :second)
  end

  # ---------------------------------------------------------------------------
  # Parsing and execution helpers
  # ---------------------------------------------------------------------------

  defp parse_interval({:every, n, :seconds}) when is_integer(n) and n > 0, do: {:ok, n}
  defp parse_interval({:every, n, :minutes}) when is_integer(n) and n > 0, do: {:ok, n * 60}
  defp parse_interval({:every, n, :hours}) when is_integer(n) and n > 0, do: {:ok, n * 3_600}
  defp parse_interval({:every, n, :days}) when is_integer(n) and n > 0, do: {:ok, n * 86_400}
  defp parse_interval(_), do: :error

  # Guard the scheduler against job crashes.  We ignore the return value —
  # interval jobs fire regardless of outcome.
  defp safe_execute({mod, fun, args}) do
    try do
      apply(mod, fun, args)
    rescue
      _ -> :crashed
    catch
      _, _ -> :crashed
    end
  end

  defp schedule_tick(:infinity), do: :ok

  defp schedule_tick(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :tick, ms)
  end
end
```

Give me only the complete implementation of `unregister` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
