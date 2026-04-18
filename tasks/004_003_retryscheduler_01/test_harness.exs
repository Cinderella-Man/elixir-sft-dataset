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
    use Agent # <--- ADDED THIS LINE TO FIX THE child_spec ERROR

    def start_link(fail_n) do
      Agent.start_link(fn -> %{remaining_failures: fail_n, attempts: 0} end, name: __MODULE__)
    end

    def attempt(test_pid) do
      state = Agent.get_and_update(__MODULE__, fn s ->
        new_state = %{s | attempts: s.attempts + 1, remaining_failures: max(0, s.remaining_failures - 1)}
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
    def ok(test_pid), do: (send(test_pid, :ran); :ok)
    def ok_tuple(test_pid), do: (send(test_pid, :ran); {:ok, :whatever})
    def err(test_pid), do: (send(test_pid, :ran); {:error, :nope})
    def err_atom(test_pid), do: (send(test_pid, :ran); :error)
    def weird_return(test_pid), do: (send(test_pid, :ran); 42)
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

  defp tick(pid) do
    send(pid, :tick)
    _ = :sys.get_state(pid)
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
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :weird_return, [self()]}, max_attempts: 1)
    tick(rs)

    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")
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
end
