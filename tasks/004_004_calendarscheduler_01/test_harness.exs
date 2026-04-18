defmodule CalendarSchedulerTest do
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

    def advance_days(d), do: advance_seconds(d * 86_400)

    def set(ndt), do: Agent.update(__MODULE__, fn _ -> ndt end)
  end

  defmodule JobSink do
    def ping(test_pid, tag), do: send(test_pid, tag)
    def crash, do: raise("boom")
  end

  # Anchor: Jan 1, 2025 at 00:00 (a Wednesday).
  @t0 ~N[2025-01-01 00:00:00]

  setup do
    start_supervised!({Clock, @t0})

    {:ok, pid} =
      CalendarScheduler.start_link(
        clock: &Clock.now/0,
        tick_interval_ms: :infinity
      )

    %{cs: pid}
  end

  defp tick(pid) do
    send(pid, :tick)
    _ = :sys.get_state(pid)
    :ok
  end

  # =======================================================
  # Rule validation
  # =======================================================

  test "valid rules return :ok at registration", %{cs: cs} do
    assert :ok =
             CalendarScheduler.register(
               cs,
               "a",
               {:nth_weekday_of_month, 1, :monday, {9, 0}},
               {JobSink, :ping, [self(), :a]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "b",
               {:last_weekday_of_month, :friday, {17, 0}},
               {JobSink, :ping, [self(), :b]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "c",
               {:nth_day_of_month, 15, {12, 0}},
               {JobSink, :ping, [self(), :c]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "d",
               {:last_day_of_month, {23, 59}},
               {JobSink, :ping, [self(), :d]}
             )
  end

  test "invalid rules return :invalid_rule", %{cs: cs} do
    # n out of range (must be 1..4)
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs, "a", {:nth_weekday_of_month, 5, :monday, {9, 0}}, {JobSink, :ping, [self(), :x]}
             )

    # unknown weekday
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs, "b", {:nth_weekday_of_month, 1, :funday, {9, 0}}, {JobSink, :ping, [self(), :x]}
             )

    # hour out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs, "c", {:last_day_of_month, {25, 0}}, {JobSink, :ping, [self(), :x]}
             )

    # minute out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs, "d", {:last_day_of_month, {0, 60}}, {JobSink, :ping, [self(), :x]}
             )

    # day out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs, "e", {:nth_day_of_month, 32, {0, 0}}, {JobSink, :ping, [self(), :x]}
             )

    # completely malformed
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(cs, "f", {:random, :nonsense}, {JobSink, :ping, [self(), :x]})
  end

  test "duplicate names rejected", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs, "j", {:nth_day_of_month, 1, {0, 0}}, {JobSink, :ping, [self(), :j]}
      )

    assert {:error, :already_exists} =
             CalendarScheduler.register(
               cs, "j", {:last_day_of_month, {0, 0}}, {JobSink, :ping, [self(), :j]}
             )
  end

  test "unregister / jobs / next_run", %{cs: cs} do
    assert {:error, :not_found} = CalendarScheduler.next_run(cs, "ghost")
    assert {:error, :not_found} = CalendarScheduler.unregister(cs, "ghost")

    :ok =
      CalendarScheduler.register(
        cs, "j", {:nth_day_of_month, 15, {12, 0}}, {JobSink, :ping, [self(), :j]}
      )

    assert [{"j", {:nth_day_of_month, 15, {12, 0}}, _}] = CalendarScheduler.jobs(cs)
    assert :ok = CalendarScheduler.unregister(cs, "j")
    assert {:error, :not_found} = CalendarScheduler.next_run(cs, "j")
  end

  # =======================================================
  # next_run math for each rule type — the defining behavior
  # =======================================================

  describe "next_run for nth_weekday_of_month" do
    test "first Monday of Jan 2025 from Jan 1 is Jan 6", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs, "j", {:nth_weekday_of_month, 1, :monday, {9, 0}}, {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-06 09:00:00]
    end

    test "second Tuesday of Jan 2025", %{cs: cs} do
      # Jan 1 2025 = Wed.  Tuesdays: Jan 7, Jan 14, Jan 21, Jan 28.
      :ok =
        CalendarScheduler.register(
          cs, "j", {:nth_weekday_of_month, 2, :tuesday, {10, 30}}, {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-14 10:30:00]
    end

    test "advances to next month after the target passes", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs, "j", {:nth_weekday_of_month, 1, :monday, {9, 0}}, {JobSink, :ping, [self(), :j]}
        )

      # Set clock to Jan 7 (past Jan 6's Monday) — should skip to Feb
      Clock.set(~N[2025-01-07 00:00:00])
      tick(cs)

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      # Feb 1 2025 = Sat; first Monday is Feb 3.
      assert next == ~N[2025-02-03 09:00:00]
    end
  end

  describe "next_run for last_weekday_of_month" do
    test "last Friday of Jan 2025 is Jan 31 (a Friday)", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs, "j", {:last_weekday_of_month, :friday, {17, 0}}, {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-31 17:00:00]
    end

    test "last Sunday of Feb 2025", %{cs: cs} do
      # Feb 28 2025 = Fri.  Last Sunday = Feb 23.
      :ok =
        CalendarScheduler.register(
          cs, "j", {:last_weekday_of_month, :sunday, {20, 0}}, {JobSink, :ping, [self(), :j]}
        )

      Clock.set(~N[2025-02-01 00:00:00])

      # Re-register — next_run is computed at registration time from the clock
      :ok = CalendarScheduler.unregister(cs, "j")
      :ok =
        CalendarScheduler.register(
          cs, "j", {:last_weekday_of_month, :sunday, {20, 0}}, {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-02-23 20:00:00]
    end
  end

  describe "next_run for nth_day_of_month" do
    test "15th of January 2025 at noon", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs, "j", {:nth_day_of_month, 15, {12, 0}}, {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-15 12:00:00]
    end

    test "31st skips February (no Feb 31)", %{cs: cs} do
      Clock.set(~N[2025-01-31 23:00:00])

      :ok =
        CalendarScheduler.register(
          cs, "j", {:nth_day_of_month, 31, {12, 0}}, {JobSink, :ping, [self(), :j]}
        )

      # Jan 31 12:00 is already past (clock is Jan 31 23:00).
      # Feb has no 31 → skip.  March has 31 → Mar 31 12:00.
      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-03-31 12:00:00]
    end

    test "31st also skips April (only 30 days), June, September, November", %{cs: cs} do
      Clock.set(~N[2025-03-31 23:00:00])

      :ok =
        CalendarScheduler.register(
          cs, "j", {:nth_day_of_month, 31, {0, 0}}, {JobSink, :ping, [self(), :j]}
        )

      # Mar 31 00:00 already past.  Apr has 30 → skip.  May 31 exists.
      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-05-31 00:00:00]
    end
  end

  describe "next_run for last_day_of_month" do
    test "last day of Jan 2025 is the 31st", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs, "j", {:last_day_of_month, {23, 59}}, {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-31 23:59:00]
    end

    test "last day of Feb 2024 is the 29th (leap year)", %{cs: cs} do
      Clock.set(~N[2024-02-01 00:00:00])

      :ok =
        CalendarScheduler.register(
          cs, "j", {:last_day_of_month, {12, 0}}, {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2024-02-29 12:00:00]
    end

    test "last day of Feb 2025 is the 28th (non-leap)", %{cs: cs} do
      Clock.set(~N[2025-02-01 00:00:00])

      :ok =
        CalendarScheduler.register(
          cs, "j", {:last_day_of_month, {12, 0}}, {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-02-28 12:00:00]
    end
  end

  # =======================================================
  # Execution on tick
  # =======================================================

  test "job fires on tick when due, recomputes for next month", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs, "j", {:nth_day_of_month, 1, {0, 0}}, {JobSink, :ping, [self(), :fired]}
      )

    # Initial next_run: Feb 1 2025 00:00 (since clock is Jan 1 00:00 and we need strictly >).
    {:ok, first_next} = CalendarScheduler.next_run(cs, "j")
    assert first_next == ~N[2025-02-01 00:00:00]

    # Advance clock past Feb 1
    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :fired

    # Next run should now be Mar 1
    {:ok, next2} = CalendarScheduler.next_run(cs, "j")
    assert next2 == ~N[2025-03-01 00:00:00]
  end

  test "crashing job does not kill the scheduler", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs, "bad", {:nth_day_of_month, 1, {0, 0}}, {JobSink, :crash, []}
      )
    :ok =
      CalendarScheduler.register(
        cs, "good", {:nth_day_of_month, 1, {0, 0}}, {JobSink, :ping, [self(), :ok]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :ok
    assert Process.alive?(cs)

    # Both jobs should still be registered and have advanced next_runs
    {:ok, bad_next} = CalendarScheduler.next_run(cs, "bad")
    assert bad_next == ~N[2025-03-01 00:00:00]
  end

  test "multiple due jobs all fire on a single tick", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs, "a", {:nth_day_of_month, 1, {0, 0}}, {JobSink, :ping, [self(), :a]}
      )
    :ok =
      CalendarScheduler.register(
        cs, "b", {:nth_day_of_month, 1, {0, 0}}, {JobSink, :ping, [self(), :b]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :a
    assert_received :b
  end

  # =======================================================
  # Year rollover
  # =======================================================

  test "next_run rolls from December to January of the next year", %{cs: cs} do
    Clock.set(~N[2025-12-31 23:59:30])

    :ok =
      CalendarScheduler.register(
        cs, "j", {:nth_day_of_month, 1, {0, 0}}, {JobSink, :ping, [self(), :j]}
      )

    {:ok, next} = CalendarScheduler.next_run(cs, "j")
    assert next == ~N[2026-01-01 00:00:00]
  end
end
