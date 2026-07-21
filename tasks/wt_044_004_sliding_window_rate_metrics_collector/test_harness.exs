defmodule MetricsTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    start_supervised!({Metrics, clock: fn -> Agent.get(clock, & &1) end})
    %{clock: clock}
  end

  defp set_time(clock, t), do: Agent.update(clock, fn _ -> t end)

  # -------------------------------------------------------
  # increment / count
  # -------------------------------------------------------

  test "increment records events at the current second", %{clock: clock} do
    set_time(clock, 0)
    assert :ok = Metrics.increment(:hits)
    Metrics.increment(:hits)
    assert Metrics.count(:hits) == 2
  end

  test "increment supports an explicit amount", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits, 5)
    Metrics.increment(:hits, 3)
    assert Metrics.count(:hits) == 8
  end

  test "count is nil-safe by returning 0 for unknown names" do
    assert Metrics.count(:unknown) == 0
  end

  # -------------------------------------------------------
  # rate
  # -------------------------------------------------------

  test "rate counts events within the window", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits)
    Metrics.increment(:hits)

    set_time(clock, 30)
    Metrics.increment(:hits)

    # now = 30, window 60 => second > -30 => all three
    assert Metrics.rate(:hits, 60) == 3
  end

  test "rate excludes events older than the window", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits)
    Metrics.increment(:hits)

    set_time(clock, 30)
    Metrics.increment(:hits)

    # now = 100, window 60 => second > 40 => none of {0,0,30}
    set_time(clock, 100)
    assert Metrics.rate(:hits, 60) == 0

    # now = 100, window 90 => second > 10 => only the event at 30
    assert Metrics.rate(:hits, 90) == 1
  end

  test "events in the same second accumulate in one bucket", %{clock: clock} do
    set_time(clock, 42)
    Metrics.increment(:hits, 4)
    Metrics.increment(:hits, 6)
    assert Metrics.rate(:hits, 1) == 10
  end

  test "rate is 0 for an unknown name", %{clock: clock} do
    set_time(clock, 5)
    assert Metrics.rate(:nope, 60) == 0
  end

  # -------------------------------------------------------
  # reset
  # -------------------------------------------------------

  test "reset deletes all buckets for a name", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits, 3)
    set_time(clock, 10)
    Metrics.increment(:hits, 2)

    Metrics.reset(:hits)
    assert Metrics.count(:hits) == 0
    assert Metrics.rate(:hits, 1000) == 0
  end

  test "reset leaves other names intact", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:a)
    Metrics.increment(:b)
    Metrics.reset(:a)
    assert Metrics.count(:a) == 0
    assert Metrics.count(:b) == 1
  end

  # -------------------------------------------------------
  # prune
  # -------------------------------------------------------

  test "prune deletes buckets older than the retention window", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits)

    set_time(clock, 50)
    Metrics.increment(:hits)

    set_time(clock, 100)
    Metrics.increment(:hits)

    # now = 100, retention 60 => delete buckets with second <= 40 => the one at 0
    assert Metrics.prune(60) == 1
    assert Metrics.count(:hits) == 2
    assert Metrics.rate(:hits, 1000) == 2
  end

  # -------------------------------------------------------
  # all
  # -------------------------------------------------------

  test "all returns per-name all-time totals", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:a, 2)
    set_time(clock, 5)
    Metrics.increment(:a, 1)
    Metrics.increment(:b, 9)

    result = Metrics.all()
    assert result[:a] == 3
    assert result[:b] == 9
  end

  # -------------------------------------------------------
  # concurrency
  # -------------------------------------------------------

  test "100 concurrent increments in the same second total 100", %{clock: clock} do
    set_time(clock, 7)

    1..100
    |> Enum.map(fn _ -> Task.async(fn -> Metrics.increment(:c, 1) end) end)
    |> Task.await_many(5_000)

    assert Metrics.count(:c) == 100
    assert Metrics.rate(:c, 1) == 100
  end

  # -------------------------------------------------------
  # hot path bypasses the owning process
  # -------------------------------------------------------

  # The owning process only holds the table; increment must reach ETS directly,
  # so it still completes while that process is unable to handle any message.
  test "increment succeeds while the owning process cannot serve requests", %{clock: clock} do
    set_time(clock, 3)
    owner = Process.whereis(Metrics)
    :sys.suspend(owner)

    task = Task.async(fn -> Metrics.increment(:direct, 4) end)
    outcome = Task.yield(task, 2_000)
    :sys.resume(owner)

    assert {:ok, :ok} = outcome
    assert Metrics.count(:direct) == 4
  end

  # Concurrent writers must not need the owning process either.
  test "concurrent increments still land while the owner is suspended", %{clock: clock} do
    set_time(clock, 11)
    owner = Process.whereis(Metrics)
    :sys.suspend(owner)

    tasks = Enum.map(1..20, fn _ -> Task.async(fn -> Metrics.increment(:busy, 2) end) end)
    outcomes = Task.yield_many(tasks, 2_000)
    :sys.resume(owner)

    assert Enum.all?(outcomes, fn {_task, result} -> result == {:ok, :ok} end)
    assert Metrics.count(:busy) == 40
  end

  # The table the owner creates must be public and named, which is what lets the
  # hot path write to it without going through the owner.
  test "the owned table is public and named" do
    owner = Process.whereis(Metrics)

    owned =
      Enum.filter(:ets.all(), fn table ->
        :ets.info(table, :owner) == owner
      end)

    assert Enum.any?(owned, fn table ->
             :ets.info(table, :protection) == :public and
               :ets.info(table, :named_table) == true
           end)
  end

  test "rate excludes a bucket sitting exactly on the window cutoff", %{clock: clock} do
    set_time(clock, 40)
    Metrics.increment(:edge, 7)

    set_time(clock, 41)
    Metrics.increment(:edge, 3)

    set_time(clock, 100)
    # cutoff = 100 - 60 = 40 => bucket 40 is excluded, bucket 41 is included
    assert Metrics.rate(:edge, 60) == 3
  end

  test "prune deletes a bucket sitting exactly on the retention cutoff", %{clock: clock} do
    set_time(clock, 40)
    Metrics.increment(:edge, 7)

    set_time(clock, 41)
    Metrics.increment(:edge, 3)

    set_time(clock, 100)
    # cutoff = 100 - 60 = 40 => bucket 40 is deleted, bucket 41 survives
    assert Metrics.prune(60) == 1
    assert Metrics.count(:edge) == 3
    assert Metrics.rate(:edge, 1000) == 3
  end

  test "prune returns the bucket count rather than the events removed", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:heavy, 5)

    set_time(clock, 1)
    Metrics.increment(:heavy, 9)

    set_time(clock, 100)
    # two buckets holding 14 events between them => 2, not 14
    assert Metrics.prune(60) == 2
    assert Metrics.count(:heavy) == 0
  end

  test "prune removes stale buckets belonging to every name", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:a, 2)
    Metrics.increment(:b, 3)

    set_time(clock, 100)
    Metrics.increment(:b, 1)

    assert Metrics.prune(60) == 2
    assert Metrics.count(:a) == 0
    assert Metrics.count(:b) == 1
    assert Metrics.all() == %{b: 1}
  end

  test "increment refuses amounts that are not non-negative integers", %{clock: clock} do
    set_time(clock, 0)

    assert_raise FunctionClauseError, fn -> Metrics.increment(:guarded, -1) end
    assert_raise FunctionClauseError, fn -> Metrics.increment(:guarded, 1.0) end

    assert Metrics.count(:guarded) == 0
    assert Metrics.rate(:guarded, 1000) == 0
  end

  test "increment accepts an amount of zero and records no events", %{clock: clock} do
    set_time(clock, 12)
    assert :ok = Metrics.increment(:zeroed, 0)

    assert Metrics.count(:zeroed) == 0
    assert Metrics.rate(:zeroed, 1) == 0

    Metrics.increment(:zeroed, 4)
    assert Metrics.count(:zeroed) == 4
  end

  # -------------------------------------------------------
  # default clock
  # -------------------------------------------------------

  # Omitting :clock must fall back to real system time in seconds rather than
  # requiring the option: starting bare still works, recording still works, and
  # events recorded moments ago fall inside a recent window.
  test "start_link works with no :clock option and buckets against system time" do
    stop_supervised!(Metrics)
    start_supervised!(Metrics)

    assert :ok = Metrics.increment(:default_clock, 2)
    assert :ok = Metrics.increment(:default_clock)

    assert Metrics.count(:default_clock) == 3
    assert Metrics.rate(:default_clock, 3600) == 3
    assert Metrics.all()[:default_clock] == 3

    # cutoff = now => a bucket stamped at or before now is never inside the window
    assert Metrics.rate(:default_clock, 0) == 0
  end
end
