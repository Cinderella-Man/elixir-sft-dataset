defmodule SchedulerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(seconds), do: Agent.update(__MODULE__, &NaiveDateTime.add(&1, seconds, :second))
    def set(dt), do: Agent.update(__MODULE__, fn _ -> dt end)
  end

  # --- Job execution tracker ---

  defmodule JobTracker do
    use Agent

    def start_link(_opts) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(name), do: Agent.update(__MODULE__, &[name | &1])
    def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1))
    def count(name), do: Agent.get(__MODULE__, fn list -> Enum.count(list, &(&1 == name)) end)
    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)
  end

  # Monday, January 5 2026, 10:00:00
  @start_time ~N[2026-01-05 10:00:00]

  setup do
    start_supervised!({Clock, @start_time})
    start_supervised!({JobTracker, []})

    {:ok, pid} =
      Scheduler.start_link(
        clock: &Clock.now/0,
        # disable auto-ticking in tests
        tick_interval_ms: :infinity
      )

    %{s: pid}
  end

  # Helper: send a :tick and wait for the GenServer to process it
  defp tick(pid) do
    send(pid, :tick)
    :sys.get_state(pid)
  end

  # -------------------------------------------------------
  # Registration
  # -------------------------------------------------------

  test "register returns :ok for a valid cron expression", %{s: s} do
    assert :ok = Scheduler.register(s, "job1", "*/5 * * * *", {JobTracker, :record, ["job1"]})
  end

  test "register returns error for too few fields", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "*/5 * *", {IO, :puts, ["hi"]})
  end

  test "register returns error for out-of-range minute (60)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "60 * * * *", {IO, :puts, ["hi"]})
  end

  test "register returns error for out-of-range hour (25)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "0 25 * * *", {IO, :puts, ["hi"]})
  end

  test "register returns error for out-of-range day-of-week (7)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "0 0 * * 7", {IO, :puts, ["hi"]})
  end

  test "register returns error for duplicate name", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})

    assert {:error, :already_exists} =
             Scheduler.register(s, "j", "*/5 * * * *", {JobTracker, :record, ["j"]})
  end

  # -------------------------------------------------------
  # Unregister
  # -------------------------------------------------------

  test "unregister returns :ok for an existing job", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})
    assert :ok = Scheduler.unregister(s, "j")
  end

  test "unregister returns error for an unknown job", %{s: s} do
    assert {:error, :not_found} = Scheduler.unregister(s, "nope")
  end

  # -------------------------------------------------------
  # Listing jobs
  # -------------------------------------------------------

  test "jobs/1 lists all registered jobs", %{s: s} do
    :ok = Scheduler.register(s, "j1", "30 11 * * *", {JobTracker, :record, ["j1"]})
    :ok = Scheduler.register(s, "j2", "0 12 * * *", {JobTracker, :record, ["j2"]})

    jobs = Scheduler.jobs(s)
    names = jobs |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    assert names == ["j1", "j2"]
  end

  test "jobs/1 returns empty list when no jobs registered", %{s: s} do
    assert Scheduler.jobs(s) == []
  end

  # -------------------------------------------------------
  # next_run calculation
  # -------------------------------------------------------

  test "next_run returns the correct next datetime for a specific time", %{s: s} do
    # At 10:00, next "30 11 * * *" is today at 11:30
    :ok = Scheduler.register(s, "j", "30 11 * * *", {JobTracker, :record, ["j"]})
    assert {:ok, ~N[2026-01-05 11:30:00]} = Scheduler.next_run(s, "j")
  end

  test "next_run wraps to next day when time has passed", %{s: s} do
    # At 10:00, "0 9 * * *" (9:00) already passed today → next is tomorrow
    :ok = Scheduler.register(s, "j", "0 9 * * *", {JobTracker, :record, ["j"]})
    assert {:ok, ~N[2026-01-06 09:00:00]} = Scheduler.next_run(s, "j")
  end

  test "next_run returns error for unknown job", %{s: s} do
    assert {:error, :not_found} = Scheduler.next_run(s, "nope")
  end

  # -------------------------------------------------------
  # Basic execution
  # -------------------------------------------------------

  test "job fires when clock reaches its scheduled time", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)

    assert JobTracker.count("j") == 1
  end

  test "job does NOT fire before its scheduled time", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:29:00])
    tick(s)

    assert JobTracker.count("j") == 0
  end

  test "job does not fire twice on the same tick", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)
    tick(s)

    assert JobTracker.count("j") == 1
  end

  # -------------------------------------------------------
  # Recurring execution
  # -------------------------------------------------------

  test "job recurs correctly after firing", %{s: s} do
    # Every hour at minute 0
    :ok = Scheduler.register(s, "j", "0 * * * *", {JobTracker, :record, ["j"]})

    # Fire at 11:00
    Clock.set(~N[2026-01-05 11:00:00])
    tick(s)
    assert JobTracker.count("j") == 1

    # After firing, next_run should advance to 12:00
    assert {:ok, ~N[2026-01-05 12:00:00]} = Scheduler.next_run(s, "j")

    # Fire again at 12:00
    Clock.set(~N[2026-01-05 12:00:00])
    tick(s)
    assert JobTracker.count("j") == 2
  end

  test "every-minute job fires each minute", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:01:00])
    tick(s)
    assert JobTracker.count("j") == 1

    Clock.set(~N[2026-01-05 10:02:00])
    tick(s)
    assert JobTracker.count("j") == 2

    Clock.set(~N[2026-01-05 10:03:00])
    tick(s)
    assert JobTracker.count("j") == 3
  end

  # -------------------------------------------------------
  # Two jobs at the same time
  # -------------------------------------------------------

  test "two jobs scheduled for the same time both fire", %{s: s} do
    :ok = Scheduler.register(s, "a", "30 10 * * *", {JobTracker, :record, ["a"]})
    :ok = Scheduler.register(s, "b", "30 10 * * *", {JobTracker, :record, ["b"]})

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)

    assert JobTracker.count("a") == 1
    assert JobTracker.count("b") == 1
  end

  # -------------------------------------------------------
  # Unregister while pending
  # -------------------------------------------------------

  test "unregistering a pending job prevents it from firing", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})
    :ok = Scheduler.unregister(s, "j")

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)

    assert JobTracker.count("j") == 0
  end

  test "re-registering after unregister works", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})
    :ok = Scheduler.unregister(s, "j")
    :ok = Scheduler.register(s, "j", "45 10 * * *", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-05 10:45:00]} = Scheduler.next_run(s, "j")

    Clock.set(~N[2026-01-05 10:45:00])
    tick(s)
    assert JobTracker.count("j") == 1
  end

  # -------------------------------------------------------
  # Cron expression features
  # -------------------------------------------------------

  test "step expression */15 fires at 0, 15, 30, 45", %{s: s} do
    :ok = Scheduler.register(s, "j", "*/15 * * * *", {JobTracker, :record, ["j"]})

    for minute <- [0, 15, 30, 45] do
      Clock.set(~N[2026-01-05 11:00:00] |> NaiveDateTime.add(minute * 60, :second))
      tick(s)
    end

    assert JobTracker.count("j") == 4
  end

  test "range expression 1-3 in hour field", %{s: s} do
    :ok = Scheduler.register(s, "j", "0 1-3 * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next match is 1:00 tomorrow (hours 1,2,3 have passed today)
    assert {:ok, next} = Scheduler.next_run(s, "j")
    assert next.hour in [1, 2, 3]
    assert next.minute == 0
    # Should be tomorrow since 1-3 are all before 10
    assert NaiveDateTime.compare(next, @start_time) == :gt
  end

  test "comma-separated values in minute field", %{s: s} do
    :ok = Scheduler.register(s, "j", "0,30 * * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next is 10:30 (advancing at least 1 minute, minute 0 is behind)
    assert {:ok, ~N[2026-01-05 10:30:00]} = Scheduler.next_run(s, "j")
  end

  test "range with step 10-30/10 matches 10, 20, 30", %{s: s} do
    :ok = Scheduler.register(s, "j", "10-30/10 * * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next is 10:10
    assert {:ok, ~N[2026-01-05 10:10:00]} = Scheduler.next_run(s, "j")

    # Fire at 10:10, next should be 10:20
    Clock.set(~N[2026-01-05 10:10:00])
    tick(s)
    assert {:ok, ~N[2026-01-05 10:20:00]} = Scheduler.next_run(s, "j")
    assert JobTracker.count("j") == 1

    # Fire at 10:20, next should be 10:30
    Clock.set(~N[2026-01-05 10:20:00])
    tick(s)
    assert {:ok, ~N[2026-01-05 10:30:00]} = Scheduler.next_run(s, "j")
    assert JobTracker.count("j") == 2
  end

  # -------------------------------------------------------
  # Day-of-week
  # -------------------------------------------------------

  test "day-of-week 0 (Sunday) schedules to next Sunday", %{s: s} do
    # We start on Monday Jan 5. Next Sunday is Jan 11.
    :ok = Scheduler.register(s, "j", "0 9 * * 0", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-11 09:00:00]} = Scheduler.next_run(s, "j")
  end

  test "day-of-week 1 (Monday) schedules to next Monday", %{s: s} do
    # We're on Monday 10:00. Next Monday-matching time at 09:00 is next week.
    :ok = Scheduler.register(s, "j", "0 9 * * 1", {JobTracker, :record, ["j"]})

    # 09:00 today already passed, so next Monday is Jan 12
    assert {:ok, ~N[2026-01-12 09:00:00]} = Scheduler.next_run(s, "j")
  end

  test "day-of-week job fires on the correct day", %{s: s} do
    # Wednesday = 3. Next Wednesday from Mon Jan 5 is Jan 7.
    :ok = Scheduler.register(s, "j", "0 12 * * 3", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-07 12:00:00]} = Scheduler.next_run(s, "j")

    Clock.set(~N[2026-01-07 12:00:00])
    tick(s)
    assert JobTracker.count("j") == 1

    # After firing, next should be the following Wednesday, Jan 14
    assert {:ok, ~N[2026-01-14 12:00:00]} = Scheduler.next_run(s, "j")
  end

  # -------------------------------------------------------
  # Specific day-of-month and month
  # -------------------------------------------------------

  test "specific day-of-month", %{s: s} do
    :ok = Scheduler.register(s, "j", "0 12 15 * *", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-15 12:00:00]} = Scheduler.next_run(s, "j")
  end

  test "specific month", %{s: s} do
    :ok = Scheduler.register(s, "j", "0 0 1 3 *", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-03-01 00:00:00]} = Scheduler.next_run(s, "j")
  end

  test "job that only matches Feb 28 in non-leap year", %{s: s} do
    # 2026 is not a leap year. "0 0 29 2 *" should skip to 2028 (next leap year)
    # Actually Feb 29 doesn't exist in 2026 or 2027. 2028 is a leap year.
    :ok = Scheduler.register(s, "j", "0 0 29 2 *", {JobTracker, :record, ["j"]})

    assert {:ok, next} = Scheduler.next_run(s, "j")
    assert next == ~N[2028-02-29 00:00:00]
  end

  # -------------------------------------------------------
  # Multiple keys interleaved
  # -------------------------------------------------------

  test "independent jobs with different schedules", %{s: s} do
    :ok = Scheduler.register(s, "fast", "*/5 * * * *", {JobTracker, :record, ["fast"]})
    :ok = Scheduler.register(s, "slow", "0 * * * *", {JobTracker, :record, ["slow"]})

    # At 10:05, "fast" fires but "slow" doesn't (next is 11:00)
    Clock.set(~N[2026-01-05 10:05:00])
    tick(s)
    assert JobTracker.count("fast") == 1
    assert JobTracker.count("slow") == 0

    # At 11:00, both fire
    Clock.set(~N[2026-01-05 11:00:00])
    tick(s)
    assert JobTracker.count("fast") == 2
    assert JobTracker.count("slow") == 1
  end
end
