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
    :ok = IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :x]})

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
             IntervalScheduler.register(is, "a", {:every, 0, :seconds}, {JobSink, :ping, [self(), :x]})

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(is, "b", {:every, -5, :seconds}, {JobSink, :ping, [self(), :x]})

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(is, "c", {:every, 5, :fortnights}, {JobSink, :ping, [self(), :x]})

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(is, "d", "every 5 seconds", {JobSink, :ping, [self(), :x]})
  end

  test "unregister returns :ok when found, :not_found otherwise", %{is: is} do
    assert {:error, :not_found} = IntervalScheduler.unregister(is, "ghost")

    :ok = IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :x]})
    assert :ok = IntervalScheduler.unregister(is, "j")
    assert {:error, :not_found} = IntervalScheduler.next_run(is, "j")
  end

  test "jobs/1 returns the registered jobs", %{is: is} do
    :ok = IntervalScheduler.register(is, "a", {:every, 10, :seconds}, {JobSink, :ping, [self(), :a]})
    :ok = IntervalScheduler.register(is, "b", {:every, 30, :minutes}, {JobSink, :ping, [self(), :b]})

    list = IntervalScheduler.jobs(is)
    assert length(list) == 2
    names = Enum.map(list, fn {n, _, _} -> n end) |> Enum.sort()
    assert names == ["a", "b"]
  end

  # -------------------------------------------------------
  # Execution on tick
  # -------------------------------------------------------

  test "jobs whose next_run is <= now are executed on tick", %{is: is} do
    :ok = IntervalScheduler.register(is, "j", {:every, 10, :seconds}, {JobSink, :ping, [self(), :fired]})

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
    :ok = IntervalScheduler.register(is, "a", {:every, 5, :seconds}, {JobSink, :ping, [self(), :a_fired]})
    :ok = IntervalScheduler.register(is, "b", {:every, 5, :seconds}, {JobSink, :ping, [self(), :b_fired]})

    Clock.advance_seconds(5)
    tick(is)

    assert_received :a_fired
    assert_received :b_fired
  end

  # -------------------------------------------------------
  # Drift-free scheduling (the defining property)
  # -------------------------------------------------------

  test "a late tick does NOT push future runs further out", %{is: is} do
    :ok = IntervalScheduler.register(is, "j", {:every, 60, :seconds}, {JobSink, :ping, [self(), :f]})

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
    :ok = IntervalScheduler.register(is, "j", {:every, 60, :seconds}, {JobSink, :ping, [self(), :f]})

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
    :ok = IntervalScheduler.register(is, "j", {:every, 10, :seconds}, {JobSink, :ping, [self(), :f]})

    # Run for 5 intervals, each with slight tick latency.
    for i <- 1..5 do
      Clock.advance_seconds(11)
      tick(is)
      assert_received :f

      # next_run should remain aligned to t0 + i*10*10... wait.  Each iteration
      # advances by 11s, so after iteration i the clock is at t0 + i*11s.  The
      # next_run is the smallest t0 + N*10 > now = t0 + i*11:
      #   N = div(i*11, 10) + 1
      {:ok, next} = IntervalScheduler.next_run(is, "j")
      expected_n = div(i * 11, 10) + 1
      expected = NaiveDateTime.add(@t0, expected_n * 10, :second)
      assert NaiveDateTime.compare(next, expected) == :eq
    end
  end

  # -------------------------------------------------------
  # Unit conversions
  # -------------------------------------------------------

  test "minutes, hours, days intervals work", %{is: is} do
    :ok = IntervalScheduler.register(is, "m", {:every, 5, :minutes}, {JobSink, :ping, [self(), :m]})
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
    :ok = IntervalScheduler.register(is, "good", {:every, 1, :seconds}, {JobSink, :ping, [self(), :g]})

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
    :ok = IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :f]})
    :ok = IntervalScheduler.unregister(is, "j")

    Clock.advance_seconds(10)
    tick(is)
    refute_received :f
  end
end
