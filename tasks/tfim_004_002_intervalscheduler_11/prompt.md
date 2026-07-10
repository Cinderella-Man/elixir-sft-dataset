# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule IntervalSchedulerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial_ndt) do
      Agent.start_link(fn -> initial_ndt end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)

    def advance_seconds(s) do
      Agent.update(__MODULE__, &NaiveDateTime.add(&1, s, :second))
    end

    def set(ndt), do: Agent.update(__MODULE__, fn _ -> ndt end)
  end

  # Small helper for test jobs that notify the test process when invoked.
  defmodule JobSink do
    def ping(test_pid, tag), do: send(test_pid, tag)
    def crash, do: raise("boom")
  end

  @t0 ~N[2025-01-01 00:00:00]

  setup do
    start_supervised!({Clock, @t0})

    {:ok, pid} =
      IntervalScheduler.start_link(
        clock: &Clock.now/0,
        # disable auto-tick — we drive ticks manually
        tick_interval_ms: :infinity
      )

    %{is: pid}
  end

  # Manually drive a tick and block until the GenServer has processed it.
  defp tick(pid) do
    send(pid, :tick)
    _ = :sys.get_state(pid)
    :ok
  end

  # -------------------------------------------------------
  # Registration basics
  # -------------------------------------------------------

  test "registering a valid interval job returns :ok", %{is: is} do
    assert :ok =
             IntervalScheduler.register(
               is,
               "job1",
               {:every, 10, :seconds},
               {JobSink, :ping, [self(), :j1]}
             )

    assert {:ok, next} = IntervalScheduler.next_run(is, "job1")
    # First fire is started_at + 10s = t0 + 10s
    assert NaiveDateTime.compare(next, NaiveDateTime.add(@t0, 10, :second)) == :eq
  end

  test "rejects duplicate names with :already_exists", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :x]})

    assert {:error, :already_exists} =
             IntervalScheduler.register(
               is,
               "j",
               {:every, 5, :seconds},
               {JobSink, :ping, [self(), :x]}
             )
  end

  test "rejects malformed interval specs with :invalid_interval", %{is: is} do
    assert {:error, :invalid_interval} =
             IntervalScheduler.register(
               is,
               "a",
               {:every, 0, :seconds},
               {JobSink, :ping, [self(), :x]}
             )

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(
               is,
               "b",
               {:every, -5, :seconds},
               {JobSink, :ping, [self(), :x]}
             )

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(
               is,
               "c",
               {:every, 5, :fortnights},
               {JobSink, :ping, [self(), :x]}
             )

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(
               is,
               "d",
               "every 5 seconds",
               {JobSink, :ping, [self(), :x]}
             )
  end

  test "unregister returns :ok when found, :not_found otherwise", %{is: is} do
    assert {:error, :not_found} = IntervalScheduler.unregister(is, "ghost")

    :ok =
      IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :x]})

    assert :ok = IntervalScheduler.unregister(is, "j")
    assert {:error, :not_found} = IntervalScheduler.next_run(is, "j")
  end

  test "jobs/1 returns the registered jobs", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "a", {:every, 10, :seconds}, {JobSink, :ping, [self(), :a]})

    :ok =
      IntervalScheduler.register(is, "b", {:every, 30, :minutes}, {JobSink, :ping, [self(), :b]})

    list = IntervalScheduler.jobs(is)
    assert length(list) == 2
    names = Enum.map(list, fn {n, _, _} -> n end) |> Enum.sort()
    assert names == ["a", "b"]
  end

  # -------------------------------------------------------
  # Execution on tick
  # -------------------------------------------------------

  test "jobs whose next_run is <= now are executed on tick", %{is: is} do
    :ok =
      IntervalScheduler.register(
        is,
        "j",
        {:every, 10, :seconds},
        {JobSink, :ping, [self(), :fired]}
      )

    # Before t0+10: not yet due
    Clock.advance_seconds(5)
    tick(is)
    refute_received :fired

    # At exactly t0+10: due
    Clock.advance_seconds(5)
    tick(is)
    assert_received :fired
  end

  test "multiple due jobs all fire on one tick", %{is: is} do
    :ok =
      IntervalScheduler.register(
        is,
        "a",
        {:every, 5, :seconds},
        {JobSink, :ping, [self(), :a_fired]}
      )

    :ok =
      IntervalScheduler.register(
        is,
        "b",
        {:every, 5, :seconds},
        {JobSink, :ping, [self(), :b_fired]}
      )

    Clock.advance_seconds(5)
    tick(is)

    assert_received :a_fired
    assert_received :b_fired
  end

  # -------------------------------------------------------
  # Drift-free scheduling (the defining property)
  # -------------------------------------------------------

  test "a late tick does NOT push future runs further out", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 60, :seconds}, {JobSink, :ping, [self(), :f]})

    # Tick arrives 1 second late (at t0 + 61s)
    Clock.advance_seconds(61)
    tick(is)
    assert_received :f

    # Next run must be t0 + 120s, NOT t0 + 121s (naive now-based scheduling would drift)
    {:ok, next} = IntervalScheduler.next_run(is, "j")
    expected = NaiveDateTime.add(@t0, 120, :second)
    assert NaiveDateTime.compare(next, expected) == :eq
  end

  test "long skip does not replay missed intervals — one fire per tick", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 60, :seconds}, {JobSink, :ping, [self(), :f]})

    # Jump 250 seconds forward — four boundaries (60, 120, 180, 240) missed
    Clock.advance_seconds(250)
    tick(is)

    # Exactly ONE message should be delivered for this tick
    assert_received :f
    refute_received :f

    # Next run is the next boundary after 250s, which is 300s
    {:ok, next} = IntervalScheduler.next_run(is, "j")
    expected = NaiveDateTime.add(@t0, 300, :second)
    assert NaiveDateTime.compare(next, expected) == :eq
  end

  test "steady-state drift-free alignment across many ticks", %{is: is} do
    # TODO
  end

  # -------------------------------------------------------
  # Unit conversions
  # -------------------------------------------------------

  test "minutes, hours, days intervals work", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "m", {:every, 5, :minutes}, {JobSink, :ping, [self(), :m]})

    :ok = IntervalScheduler.register(is, "h", {:every, 2, :hours}, {JobSink, :ping, [self(), :h]})
    :ok = IntervalScheduler.register(is, "d", {:every, 1, :days}, {JobSink, :ping, [self(), :d]})

    {:ok, m_next} = IntervalScheduler.next_run(is, "m")
    {:ok, h_next} = IntervalScheduler.next_run(is, "h")
    {:ok, d_next} = IntervalScheduler.next_run(is, "d")

    assert NaiveDateTime.diff(m_next, @t0, :second) == 300
    assert NaiveDateTime.diff(h_next, @t0, :second) == 7_200
    assert NaiveDateTime.diff(d_next, @t0, :second) == 86_400
  end

  # -------------------------------------------------------
  # Crashes don't kill the scheduler
  # -------------------------------------------------------

  test "a crashing job does not kill the scheduler", %{is: is} do
    :ok = IntervalScheduler.register(is, "bad", {:every, 1, :seconds}, {JobSink, :crash, []})

    :ok =
      IntervalScheduler.register(
        is,
        "good",
        {:every, 1, :seconds},
        {JobSink, :ping, [self(), :g]}
      )

    Clock.advance_seconds(1)
    tick(is)

    # Scheduler survived — good job still fired
    assert_received :g
    assert Process.alive?(is)

    # And the bad job is still registered; its next_run has advanced.
    {:ok, bad_next} = IntervalScheduler.next_run(is, "bad")
    assert NaiveDateTime.compare(bad_next, Clock.now()) == :gt
  end

  # -------------------------------------------------------
  # Unregister stops execution
  # -------------------------------------------------------

  test "unregistered jobs do not fire", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :f]})

    :ok = IntervalScheduler.unregister(is, "j")

    Clock.advance_seconds(10)
    tick(is)
    refute_received :f
  end
end
```
