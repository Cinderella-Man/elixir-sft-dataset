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

  # -------------------------------------------------------
  # process registration (:name option)
  # -------------------------------------------------------

  defp unique_name do
    :"metrics_#{System.pid()}_#{System.unique_integer([:positive])}"
  end

  test "start_link without :name registers the process under the module name" do
    assert is_pid(Process.whereis(Metrics))
  end

  test "start_link registers the process under a custom :name" do
    stop_supervised(Metrics)
    name = unique_name()
    pid = start_supervised!({Metrics, name: name})

    assert Process.whereis(name) == pid
    assert :ok = Metrics.observe(:named, 42)
    assert Metrics.get(:named).count == 1
  end

  test "a custom :name is not mistaken for bucket configuration" do
    stop_supervised(Metrics)
    name = unique_name()
    start_supervised!({Metrics, name: name, buckets: [1, 2, 3]})

    Metrics.observe(:named_buckets, 2)
    b = Metrics.get(:named_buckets).buckets
    assert b[1] == 0
    assert b[2] == 1
    assert b[3] == 1
    assert b[:infinity] == 1
  end
end
