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
end