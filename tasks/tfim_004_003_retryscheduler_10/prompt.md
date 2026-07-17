# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule RetryScheduler do
  @moduledoc """
  A GenServer that runs **one-shot** jobs at a specified future time with
  exponential-backoff retries on failure.

  Each job has a bounded lifecycle:

      :pending  -(success)->   :completed  (terminal)
      :pending  -(failure, retries left)->  :pending (with later next_attempt_at)
      :pending  -(failure, no retries)->   :dead    (terminal)

  Terminal jobs remain in the registry for inspection via `status/2` and
  `jobs/1`.  They are never re-executed but can be removed via `cancel/2`.

  Retry delays grow geometrically:
  `delay_ms = base_delay_ms * backoff_factor^(attempts_so_far - 1)`.
  So the first retry (after failure #1) waits `base_delay_ms`, the second
  retry waits `base_delay_ms * backoff_factor`, and so on.

  An attempt is classified as **success** when the mfa returns `:ok` or
  `{:ok, _}`.  Anything else — `:error`, `{:error, _}`, an unexpected return
  value, a raised exception, or a thrown value — counts as **failure**.

  ## Options

    * `:name`              – process registration name (optional)
    * `:clock`             – zero-arity function returning a `NaiveDateTime`
                             (default: `fn -> NaiveDateTime.utc_now() end`)
    * `:tick_interval_ms`  – polling interval in ms; `:infinity` disables
                             auto-ticking (default `1_000`)

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

  @spec schedule(
          GenServer.server(),
          term(),
          NaiveDateTime.t(),
          {module(), atom(), list()},
          keyword()
        ) ::
          :ok | {:error, :already_exists | :invalid_opts}
  @doc """
  Schedules `mfa` to run at `run_at` under `job_name`, retrying with geometric backoff
  per `opts`. Returns `:ok`, `{:error, :already_exists}` when `job_name` is already
  scheduled, or `{:error, :invalid_opts}` when `opts` fail validation.
  """
  def schedule(server, job_name, %NaiveDateTime{} = run_at, {mod, fun, args} = mfa, opts \\ [])
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:schedule, job_name, run_at, mfa, opts})
  end

  @spec cancel(GenServer.server(), term()) :: :ok | {:error, :not_found}
  def cancel(server, job_name), do: GenServer.call(server, {:cancel, job_name})

  @spec status(GenServer.server(), term()) ::
          {:ok, :pending | :completed | :dead, non_neg_integer()}
          | {:error, :not_found}
  def status(server, job_name), do: GenServer.call(server, {:status, job_name})

  @spec jobs(GenServer.server()) ::
          [{term(), :pending | :completed | :dead, NaiveDateTime.t(), non_neg_integer()}]
  def jobs(server), do: GenServer.call(server, :jobs)

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
  def handle_call({:schedule, name, run_at, mfa, opts}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        case validate_opts(opts) do
          {:ok, max_attempts, base_delay_ms, backoff_factor} ->
            job = %{
              mfa: mfa,
              status: :pending,
              attempts_so_far: 0,
              next_attempt_at: run_at,
              max_attempts: max_attempts,
              base_delay_ms: base_delay_ms,
              backoff_factor: backoff_factor
            }

            {:reply, :ok, %{state | jobs: Map.put(state.jobs, name, job)}}

          :error ->
            {:reply, {:error, :invalid_opts}, state}
        end
    end
  end

  def handle_call({:cancel, name}, _from, state) do
    case Map.pop(state.jobs, name) do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_, new_jobs} -> {:reply, :ok, %{state | jobs: new_jobs}}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, job} -> {:reply, {:ok, job.status, job.attempts_so_far}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:jobs, _from, state) do
    list =
      Enum.map(state.jobs, fn {name, j} ->
        {name, j.status, j.next_attempt_at, j.attempts_so_far}
      end)

    {:reply, list, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = state.clock.()

    new_jobs =
      Enum.reduce(state.jobs, %{}, fn {name, job}, acc ->
        updated =
          if job.status == :pending and NaiveDateTime.compare(job.next_attempt_at, now) != :gt do
            process_attempt(job, now)
          else
            job
          end

        Map.put(acc, name, updated)
      end)

    schedule_tick(state.tick_interval_ms)
    {:noreply, %{state | jobs: new_jobs}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Attempt processing — the heart of the retry logic
  # ---------------------------------------------------------------------------

  defp process_attempt(job, now) do
    outcome = safe_execute(job.mfa)
    attempts = job.attempts_so_far + 1

    case outcome do
      :success ->
        %{job | status: :completed, attempts_so_far: attempts, next_attempt_at: now}

      :failure when attempts >= job.max_attempts ->
        %{job | status: :dead, attempts_so_far: attempts, next_attempt_at: now}

      :failure ->
        delay_ms = round(job.base_delay_ms * :math.pow(job.backoff_factor, attempts - 1))
        next = NaiveDateTime.add(now, delay_ms, :millisecond)

        %{
          job
          | status: :pending,
            attempts_so_far: attempts,
            next_attempt_at: next
        }
    end
  end

  # Runs the mfa inside a try/rescue/catch and classifies the outcome.
  defp safe_execute({mod, fun, args}) do
    try do
      case apply(mod, fun, args) do
        :ok -> :success
        {:ok, _} -> :success
        _ -> :failure
      end
    rescue
      _ -> :failure
    catch
      _, _ -> :failure
    end
  end

  # ---------------------------------------------------------------------------
  # Option validation
  # ---------------------------------------------------------------------------

  defp validate_opts(opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 1_000)
    backoff_factor = Keyword.get(opts, :backoff_factor, 2.0)

    cond do
      not is_integer(max_attempts) or max_attempts < 1 -> :error
      not is_integer(base_delay_ms) or base_delay_ms < 0 -> :error
      not is_number(backoff_factor) or backoff_factor < 1.0 -> :error
      true -> {:ok, max_attempts, base_delay_ms, backoff_factor * 1.0}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp schedule_tick(:infinity), do: :ok

  defp schedule_tick(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :tick, ms)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RetrySchedulerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial_ndt) do
      Agent.start_link(fn -> initial_ndt end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)

    def advance_ms(ms) do
      Agent.update(__MODULE__, &NaiveDateTime.add(&1, ms, :millisecond))
    end

    def set(ndt), do: Agent.update(__MODULE__, fn _ -> ndt end)
  end

  # Programmable job that consults an Agent counter to decide whether to
  # succeed on this attempt. Useful for "fail N times, then succeed" tests.
  defmodule Flaky do
    use Agent

    def start_link(fail_n) do
      Agent.start_link(fn -> %{remaining_failures: fail_n, attempts: 0} end, name: __MODULE__)
    end

    def attempt(test_pid) do
      state =
        Agent.get_and_update(__MODULE__, fn s ->
          new_state = %{
            s
            | attempts: s.attempts + 1,
              remaining_failures: max(0, s.remaining_failures - 1)
          }

          {s, new_state}
        end)

      send(test_pid, {:flaky_attempt, state.attempts + 1})

      if state.remaining_failures > 0 do
        {:error, :planned_failure}
      else
        {:ok, :done}
      end
    end

    def attempts, do: Agent.get(__MODULE__, & &1.attempts)
  end

  defmodule JobSink do
    def ok(test_pid),
      do:
        (
          send(test_pid, :ran)
          :ok
        )

    def ok_tuple(test_pid),
      do:
        (
          send(test_pid, :ran)
          {:ok, :whatever}
        )

    def err(test_pid),
      do:
        (
          send(test_pid, :ran)
          {:error, :nope}
        )

    def err_atom(test_pid),
      do:
        (
          send(test_pid, :ran)
          :error
        )

    def weird_return(test_pid),
      do:
        (
          send(test_pid, :ran)
          42
        )

    def crash, do: raise("boom")
    def throw_value, do: throw(:thrown)
  end

  @t0 ~N[2025-01-01 00:00:00]

  setup do
    start_supervised!({Clock, @t0})

    {:ok, pid} =
      RetryScheduler.start_link(
        clock: &Clock.now/0,
        tick_interval_ms: :infinity
      )

    %{rs: pid}
  end

  # Delivers a tick, then issues a synchronous public-API read. Because the
  # server handles messages in order, the read cannot be answered until the
  # tick has been fully processed, so it acts as a barrier.
  defp tick(pid) do
    send(pid, :tick)
    _ = RetryScheduler.jobs(pid)
    :ok
  end

  # -------------------------------------------------------
  # Registration & validation
  # -------------------------------------------------------

  test "schedule with valid args returns :ok", %{rs: rs} do
    assert :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")
  end

  test "duplicate name returns :already_exists", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})

    assert {:error, :already_exists} =
             RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
  end

  test "invalid opts return :invalid_opts", %{rs: rs} do
    assert {:error, :invalid_opts} =
             RetryScheduler.schedule(rs, "a", @t0, {JobSink, :ok, [self()]}, max_attempts: 0)

    assert {:error, :invalid_opts} =
             RetryScheduler.schedule(rs, "b", @t0, {JobSink, :ok, [self()]}, backoff_factor: 0.5)

    assert {:error, :invalid_opts} =
             RetryScheduler.schedule(rs, "c", @t0, {JobSink, :ok, [self()]}, base_delay_ms: -1)
  end

  test "cancel removes a job; unknown cancel returns :not_found", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    assert :ok = RetryScheduler.cancel(rs, "j")
    assert {:error, :not_found} = RetryScheduler.status(rs, "j")
    assert {:error, :not_found} = RetryScheduler.cancel(rs, "j")
  end

  # -------------------------------------------------------
  # Outcome classification
  # -------------------------------------------------------

  test "returning :ok counts as success", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    tick(rs)

    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end

  test "returning {:ok, _} counts as success", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok_tuple, [self()]})
    tick(rs)

    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end

  test "returning :error counts as failure", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :err_atom, [self()]}, max_attempts: 1)
    tick(rs)

    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")
  end

  test "returning {:error, _} counts as failure", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :err, [self()]}, max_attempts: 1)
    tick(rs)

    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")
  end

  test "unexpected return values count as failure", %{rs: rs} do
    # TODO
  end

  test "raised exceptions count as failure, scheduler survives", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :crash, []}, max_attempts: 1)
    tick(rs)

    assert Process.alive?(rs)
    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")
  end

  test "thrown values count as failure, scheduler survives", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :throw_value, []}, max_attempts: 1)
    tick(rs)

    assert Process.alive?(rs)
    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")
  end

  # -------------------------------------------------------
  # Backoff math (the defining property)
  # -------------------------------------------------------

  test "first retry uses base_delay_ms", %{rs: rs} do
    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {JobSink, :err, [self()]},
        max_attempts: 3,
        base_delay_ms: 1_000,
        backoff_factor: 2.0
      )

    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    # First retry should be scheduled base_delay_ms (1000ms) after now
    [{_, :pending, next, 1}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next, @t0, :millisecond) == 1_000
  end

  test "retry delays follow base * factor^(n-1)", %{rs: rs} do
    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {JobSink, :err, [self()]},
        max_attempts: 4,
        base_delay_ms: 100,
        backoff_factor: 2.0
      )

    # Attempt 1 (fails at t=0) → retry scheduled at t=100ms
    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    # Jump to retry 1 — fails → retry scheduled at t=100 + 200 = 300ms
    Clock.advance_ms(100)
    tick(rs)
    assert {:ok, :pending, 2} = RetryScheduler.status(rs, "j")

    [{_, :pending, next2, 2}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next2, @t0, :millisecond) == 100 + 200

    # Jump to retry 2 — fails → retry scheduled base*factor^2 = 400ms later
    Clock.advance_ms(200)
    tick(rs)
    assert {:ok, :pending, 3} = RetryScheduler.status(rs, "j")

    [{_, :pending, next3, 3}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next3, @t0, :millisecond) == 700
  end

  test "job transitions to :dead after max_attempts failures", %{rs: rs} do
    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {JobSink, :err, [self()]},
        max_attempts: 3,
        base_delay_ms: 10,
        backoff_factor: 2.0
      )

    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    Clock.advance_ms(10)
    tick(rs)
    assert {:ok, :pending, 2} = RetryScheduler.status(rs, "j")

    Clock.advance_ms(20)
    tick(rs)
    assert {:ok, :dead, 3} = RetryScheduler.status(rs, "j")

    # Further ticks do NOT re-execute a :dead job
    Clock.advance_ms(1_000_000)
    tick(rs)
    assert {:ok, :dead, 3} = RetryScheduler.status(rs, "j")
  end

  # -------------------------------------------------------
  # The flaky-success scenario
  # -------------------------------------------------------

  test "a job that fails twice then succeeds ends :completed with 3 attempts", %{rs: rs} do
    start_supervised!({Flaky, 2})

    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {Flaky, :attempt, [self()]},
        max_attempts: 5,
        base_delay_ms: 10,
        backoff_factor: 2.0
      )

    # Attempt 1 fails
    tick(rs)
    assert_received {:flaky_attempt, 1}
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    # Attempt 2 fails (after 10ms backoff)
    Clock.advance_ms(10)
    tick(rs)
    assert_received {:flaky_attempt, 2}
    assert {:ok, :pending, 2} = RetryScheduler.status(rs, "j")

    # Attempt 3 succeeds (after 20ms backoff)
    Clock.advance_ms(20)
    tick(rs)
    assert_received {:flaky_attempt, 3}
    assert {:ok, :completed, 3} = RetryScheduler.status(rs, "j")

    # Further ticks don't re-run a :completed job
    Clock.advance_ms(1_000_000)
    tick(rs)
    refute_received {:flaky_attempt, _}
  end

  # -------------------------------------------------------
  # run_at in the past
  # -------------------------------------------------------

  test "run_at in the past fires on next tick", %{rs: rs} do
    past = NaiveDateTime.add(@t0, -3_600, :second)
    :ok = RetryScheduler.schedule(rs, "j", past, {JobSink, :ok, [self()]})

    tick(rs)
    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end

  # -------------------------------------------------------
  # run_at in the future is respected
  # -------------------------------------------------------

  test "job does not fire before run_at", %{rs: rs} do
    future = NaiveDateTime.add(@t0, 100, :second)
    :ok = RetryScheduler.schedule(rs, "j", future, {JobSink, :ok, [self()]})

    tick(rs)
    refute_received :ran
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")

    # Advance just past run_at
    Clock.advance_ms(100_001)
    tick(rs)
    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end

  # -------------------------------------------------------
  # Cancellation stops retries
  # -------------------------------------------------------

  test "cancelled job does not run further attempts", %{rs: rs} do
    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {JobSink, :err, [self()]},
        max_attempts: 5,
        base_delay_ms: 10
      )

    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    assert :ok = RetryScheduler.cancel(rs, "j")

    Clock.advance_ms(1_000_000)
    tick(rs)
    assert {:error, :not_found} = RetryScheduler.status(rs, "j")
  end

  # -------------------------------------------------------
  # Automatic ticking driven by :tick_interval_ms
  # -------------------------------------------------------

  test "a server with a finite tick interval runs a due job with no manual tick" do
    {:ok, rs} = RetryScheduler.start_link(clock: &Clock.now/0, tick_interval_ms: 10)

    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})

    # Nothing but the scheduler's own periodic tick can drive this attempt.
    assert_receive :ran, 2_000
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end

  test "auto-ticking keeps firing, so a job due later still runs" do
    {:ok, rs} = RetryScheduler.start_link(clock: &Clock.now/0, tick_interval_ms: 10)

    future = NaiveDateTime.add(@t0, 60, :second)
    :ok = RetryScheduler.schedule(rs, "j", future, {JobSink, :ok, [self()]})

    # Early ticks find the job not yet due and must leave it alone.
    refute_receive :ran, 150
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")

    # Once the clock passes run_at, a later tick must still arrive: the
    # scheduler re-arms its timer after every tick.
    Clock.advance_ms(60_001)
    assert_receive :ran, 2_000
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end

  test "tick_interval_ms :infinity never auto-ticks; only manual ticks run jobs", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})

    # The job is due immediately, yet auto-ticking is disabled.
    refute_receive :ran, 300
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")

    tick(rs)
    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end

  # -------------------------------------------------------
  # Cancellation from terminal states
  # -------------------------------------------------------

  test "cancel removes a :completed job", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    tick(rs)
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")

    assert :ok = RetryScheduler.cancel(rs, "j")
    assert {:error, :not_found} = RetryScheduler.status(rs, "j")
    assert [] = RetryScheduler.jobs(rs)
  end

  test "cancel removes a :dead job", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :err, [self()]}, max_attempts: 1)
    tick(rs)
    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")

    assert :ok = RetryScheduler.cancel(rs, "j")
    assert {:error, :not_found} = RetryScheduler.status(rs, "j")
    assert [] = RetryScheduler.jobs(rs)
  end

  test "a name freed by cancelling a terminal job can be scheduled again", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    tick(rs)
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
    assert_received :ran

    assert :ok = RetryScheduler.cancel(rs, "j")
    assert :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")
  end

  test "default max_attempts, base_delay_ms and backoff_factor drive backoff and death",
       %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :err, [self()]})

    # Attempt 1 fails; default base_delay_ms (1_000) schedules the first retry.
    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")
    [{_, :pending, next1, 1}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next1, @t0, :millisecond) == 1_000

    # Attempt 2 fails; default backoff_factor (2.0) makes the next delay 2_000.
    Clock.advance_ms(1_000)
    tick(rs)
    assert {:ok, :pending, 2} = RetryScheduler.status(rs, "j")
    [{_, :pending, next2, 2}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next2, @t0, :millisecond) == 3_000

    # Attempt 3 fails; default max_attempts (3) is the total, so the job dies.
    Clock.advance_ms(2_000)
    tick(rs)
    assert {:ok, :dead, 3} = RetryScheduler.status(rs, "j")
  end

  test "backoff_factor of exactly 1.0 is accepted and keeps delays constant", %{rs: rs} do
    assert :ok =
             RetryScheduler.schedule(
               rs,
               "j",
               @t0,
               {JobSink, :err, [self()]},
               max_attempts: 4,
               base_delay_ms: 50,
               backoff_factor: 1.0
             )

    tick(rs)
    [{_, :pending, next1, 1}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next1, @t0, :millisecond) == 50

    Clock.advance_ms(50)
    tick(rs)
    [{_, :pending, next2, 2}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next2, @t0, :millisecond) == 100
  end

  test "jobs lists a completed job with a next_attempt_at timestamp", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    tick(rs)
    assert_received :ran

    assert [{"j", :completed, %NaiveDateTime{}, 1}] = RetryScheduler.jobs(rs)
  end
end
```
