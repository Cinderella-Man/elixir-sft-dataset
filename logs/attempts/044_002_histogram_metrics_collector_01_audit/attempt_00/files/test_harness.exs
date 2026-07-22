defmodule MetricsTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Metrics)
    :ok
  end

  # -------------------------------------------------------
  # observe / get basics
  # -------------------------------------------------------

  test "get returns nil for a histogram that has never been observed" do
    assert Metrics.get(:never) == nil
  end

  test "a single observation produces count 1 and matching sum" do
    assert :ok = Metrics.observe(:lat, 42)
    summary = Metrics.get(:lat)
    assert summary.count == 1
    assert summary.sum == 42
    assert_in_delta summary.average, 42.0, 0.0001
  end

  test "count, sum and average accumulate across observations" do
    Metrics.observe(:lat, 5)
    Metrics.observe(:lat, 42)
    Metrics.observe(:lat, 42)
    summary = Metrics.get(:lat)
    assert summary.count == 3
    assert summary.sum == 89
    assert_in_delta summary.average, 89 / 3, 0.0001
  end

  # -------------------------------------------------------
  # cumulative buckets
  # -------------------------------------------------------

  test "buckets are cumulative (less-than-or-equal)" do
    Metrics.observe(:lat, 5)
    Metrics.observe(:lat, 42)
    Metrics.observe(:lat, 42)
    b = Metrics.get(:lat).buckets
    assert b[10] == 1
    assert b[50] == 3
    assert b[100] == 3
    assert b[500] == 3
    assert b[1000] == 3
    assert b[:infinity] == 3
  end

  test "values above every boundary land only in the +Inf bucket" do
    Metrics.observe(:big, 5000)
    b = Metrics.get(:big).buckets
    assert b[10] == 0
    assert b[1000] == 0
    assert b[:infinity] == 1
    assert Metrics.get(:big).sum == 5000
  end

  test "a value exactly on a boundary is included at that boundary" do
    Metrics.observe(:edge, 50)
    b = Metrics.get(:edge).buckets
    assert b[10] == 0
    assert b[50] == 1
    assert b[100] == 1
  end

  # -------------------------------------------------------
  # custom buckets
  # -------------------------------------------------------

  test "custom bucket boundaries are honoured" do
    stop_supervised(Metrics)
    start_supervised!({Metrics, buckets: [1, 2, 3]})
    Metrics.observe(:x, 2)
    b = Metrics.get(:x).buckets
    assert b[1] == 0
    assert b[2] == 1
    assert b[3] == 1
    assert b[:infinity] == 1
  end

  # -------------------------------------------------------
  # all / reset
  # -------------------------------------------------------

  test "all returns a map of name => total count" do
    Metrics.observe(:a, 1)
    Metrics.observe(:a, 2)
    Metrics.observe(:b, 900)
    result = Metrics.all()
    assert result[:a] == 2
    assert result[:b] == 1
  end

  test "reset erases a histogram entirely" do
    Metrics.observe(:gone, 10)
    assert Metrics.get(:gone).count == 1
    Metrics.reset(:gone)
    assert Metrics.get(:gone) == nil
    assert Metrics.all()[:gone] == nil
  end

  test "reset of one histogram leaves others intact" do
    Metrics.observe(:keep, 3)
    Metrics.observe(:drop, 3)
    Metrics.reset(:drop)
    assert Metrics.get(:drop) == nil
    assert Metrics.get(:keep).count == 1
  end

  # -------------------------------------------------------
  # concurrency
  # -------------------------------------------------------

  test "100 concurrent observations aggregate correctly" do
    1..100
    |> Enum.map(fn _ -> Task.async(fn -> Metrics.observe(:c, 7) end) end)
    |> Task.await_many(5_000)

    summary = Metrics.get(:c)
    assert summary.count == 100
    assert summary.sum == 700
    assert summary.buckets[10] == 100
  end

  test "observe rejects negative and non-integer values but accepts zero" do
    assert_raise FunctionClauseError, fn -> Metrics.observe(:guarded, -1) end
    assert_raise FunctionClauseError, fn -> Metrics.observe(:guarded, 1.5) end
    assert_raise FunctionClauseError, fn -> Metrics.observe(:guarded, "10") end
    assert Metrics.get(:guarded) == nil

    assert :ok = Metrics.observe(:zero, 0)
    summary = Metrics.get(:zero)
    assert summary.count == 1
    assert summary.sum == 0
    assert summary.buckets[10] == 1
  end

  test "observe and get keep working while the owning GenServer is unavailable" do
    :sys.suspend(Metrics)

    try do
      assert :ok = Metrics.observe(:hot, 7)
      assert :ok = Metrics.observe(:hot, 7)
      summary = Metrics.get(:hot)
      assert summary.count == 2
      assert summary.sum == 14
      assert summary.buckets[10] == 2
      assert Metrics.all()[:hot] == 2
    after
      :sys.resume(Metrics)
    end
  end

  test "default bucket boundaries are exactly the documented list" do
    Metrics.observe(:defaults, 1)
    keys = Metrics.get(:defaults).buckets |> Map.keys() |> Enum.sort()
    assert keys == [10, 50, 100, 500, 1000, :infinity]
  end

  test "a value exactly equal to the largest boundary is not treated as +Inf only" do
    Metrics.observe(:top, 1000)
    b = Metrics.get(:top).buckets
    assert b[500] == 0
    assert b[1000] == 1
    assert b[:infinity] == 1

    Metrics.observe(:top, 1001)
    b2 = Metrics.get(:top).buckets
    assert b2[1000] == 1
    assert b2[:infinity] == 2
  end

  test "observing after a reset starts from a clean slate with no leftover counters" do
    Metrics.observe(:recycled, 5)
    Metrics.observe(:recycled, 5000)
    assert Metrics.get(:recycled).count == 2

    assert :ok = Metrics.reset(:recycled)
    assert Metrics.get(:recycled) == nil

    Metrics.observe(:recycled, 5)
    summary = Metrics.get(:recycled)
    assert summary.count == 1
    assert summary.sum == 5
    assert summary.buckets[10] == 1
    assert summary.buckets[:infinity] == 1
    assert Metrics.all()[:recycled] == 1
  end
end
