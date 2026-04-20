Implement the private `parse_interval/1` function to convert an interval specification into a raw count of seconds.

The function should pattern match on a tuple of the form `{:every, n, unit}`. It must support the following units:
* `:seconds` (1:1)
* `:minutes` (60 seconds)
* `:hours` (3,600 seconds)
* `:days` (86,400 seconds)

Ensure that `n` is a positive integer. If the input matches a valid specification, return `{:ok, total_seconds}`. For any other input—including non-positive integers or unknown units—return `:error`.

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
      iex> :ok = IntervalScheduler.register(pid, "heartbeat", {:every, 30, :seconds}, {IO, :puts, ["tick"]})

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
  def register(server, job_name, interval_spec, {mod, fun, args} = mfa)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, job_name, interval_spec, mfa})
  end

  @spec unregister(GenServer.server(), term()) :: :ok | {:error, :not_found}
  def unregister(server, job_name) do
    GenServer.call(server, {:unregister, job_name})
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

  # TODO defp parse_interval  

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