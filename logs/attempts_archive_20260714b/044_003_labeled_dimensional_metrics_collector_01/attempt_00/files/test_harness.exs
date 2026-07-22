defmodule MetricsTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Metrics)
    :ok
  end

  # -------------------------------------------------------
  # labeled increments
  # -------------------------------------------------------

  test "increment without labels uses the empty label set" do
    Metrics.increment(:requests)
    assert Metrics.get(:requests, %{}) == 1
  end

  test "same name with different labels are independent series" do
    Metrics.increment(:requests, %{method: "GET"})
    Metrics.increment(:requests, %{method: "GET"})
    Metrics.increment(:requests, %{method: "POST"})
    assert Metrics.get(:requests, %{method: "GET"}) == 2
    assert Metrics.get(:requests, %{method: "POST"}) == 1
  end

  test "label order does not matter — same series" do
    Metrics.increment(:hits, %{a: 1, b: 2})
    Metrics.increment(:hits, %{b: 2, a: 1})
    assert Metrics.get(:hits, %{a: 1, b: 2}) == 2
  end

  test "increment supports name+amount without labels" do
    Metrics.increment(:bytes, 500)
    Metrics.increment(:bytes, 250)
    assert Metrics.get(:bytes, %{}) == 750
  end

  test "increment supports name+labels+amount" do
    Metrics.increment(:bytes, %{route: "/x"}, 10)
    Metrics.increment(:bytes, %{route: "/x"}, 5)
    assert Metrics.get(:bytes, %{route: "/x"}) == 15
  end

  # -------------------------------------------------------
  # aggregate get/1
  # -------------------------------------------------------

  test "get/1 aggregates across all label combinations" do
    Metrics.increment(:requests, %{method: "GET"}, 3)
    Metrics.increment(:requests, %{method: "POST"}, 4)
    Metrics.increment(:requests, %{method: "PUT"}, 1)
    assert Metrics.get(:requests) == 8
  end

  test "get/1 returns nil when the name has no series" do
    assert Metrics.get(:unknown) == nil
  end

  test "get/2 returns nil for an unknown series" do
    Metrics.increment(:requests, %{method: "GET"})
    assert Metrics.get(:requests, %{method: "DELETE"}) == nil
  end

  # -------------------------------------------------------
  # gauges
  # -------------------------------------------------------

  test "gauge without labels sets exact value" do
    Metrics.gauge(:temp, 72)
    assert Metrics.get(:temp, %{}) == 72
  end

  test "gauge with labels overwrites the series" do
    Metrics.gauge(:temp, %{room: "kitchen"}, 20)
    Metrics.gauge(:temp, %{room: "kitchen"}, 25)
    assert Metrics.get(:temp, %{room: "kitchen"}) == 25
  end

  # -------------------------------------------------------
  # series/1
  # -------------------------------------------------------

  test "series lists every label combination with its value" do
    Metrics.increment(:requests, %{method: "GET"}, 2)
    Metrics.increment(:requests, %{method: "POST"}, 5)
    series = Metrics.series(:requests)
    assert length(series) == 2
    assert %{labels: %{method: "GET"}, value: 2} in series
    assert %{labels: %{method: "POST"}, value: 5} in series
  end

  test "series is empty for an unknown name" do
    assert Metrics.series(:nope) == []
  end

  # -------------------------------------------------------
  # reset
  # -------------------------------------------------------

  test "reset/2 zeroes one specific series" do
    Metrics.increment(:requests, %{method: "GET"}, 5)
    Metrics.increment(:requests, %{method: "POST"}, 9)
    Metrics.reset(:requests, %{method: "GET"})
    assert Metrics.get(:requests, %{method: "GET"}) == 0
    assert Metrics.get(:requests, %{method: "POST"}) == 9
  end

  test "reset/1 zeroes every series under the name" do
    Metrics.increment(:requests, %{method: "GET"}, 5)
    Metrics.increment(:requests, %{method: "POST"}, 9)
    Metrics.reset(:requests)
    assert Metrics.get(:requests) == 0
    assert Metrics.get(:requests, %{method: "GET"}) == 0
    assert Metrics.get(:requests, %{method: "POST"}) == 0
  end

  # -------------------------------------------------------
  # all
  # -------------------------------------------------------

  test "all is keyed by {name, labels}" do
    Metrics.increment(:a, %{k: 1}, 3)
    Metrics.gauge(:b, %{k: 2}, 42)
    result = Metrics.all()
    assert result[{:a, %{k: 1}}] == 3
    assert result[{:b, %{k: 2}}] == 42
  end

  # -------------------------------------------------------
  # concurrency
  # -------------------------------------------------------

  test "100 concurrent increments on the same series total 100" do
    1..100
    |> Enum.map(fn _ ->
      Task.async(fn -> Metrics.increment(:c, %{shard: "a"}, 1) end)
    end)
    |> Task.await_many(5_000)

    assert Metrics.get(:c, %{shard: "a"}) == 100
  end

  test "concurrent increments across distinct label sets stay independent" do
    tasks =
      Enum.map(1..50, fn _ -> Task.async(fn -> Metrics.increment(:c, %{s: 1}, 1) end) end) ++
        Enum.map(1..50, fn _ -> Task.async(fn -> Metrics.increment(:c, %{s: 2}, 1) end) end)

    Task.await_many(tasks, 5_000)

    assert Metrics.get(:c, %{s: 1}) == 50
    assert Metrics.get(:c, %{s: 2}) == 50
    assert Metrics.get(:c) == 100
  end
end