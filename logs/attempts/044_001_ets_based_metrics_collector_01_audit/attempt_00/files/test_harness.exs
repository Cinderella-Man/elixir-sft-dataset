defmodule MetricsTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Metrics)
    :ok
  end

  # -------------------------------------------------------
  # Counters
  # -------------------------------------------------------

  test "increment creates a counter starting at 1" do
    assert :ok = Metrics.increment(:hits)
    assert Metrics.get(:hits) == 1
  end

  test "increment adds the given amount" do
    Metrics.increment(:hits, 5)
    Metrics.increment(:hits, 3)
    assert Metrics.get(:hits) == 8
  end

  test "increment defaults amount to 1" do
    Metrics.increment(:clicks)
    Metrics.increment(:clicks)
    Metrics.increment(:clicks)
    assert Metrics.get(:hits) == nil
    assert Metrics.get(:clicks) == 3
  end

  test "counters are monotonically increasing — reset brings back to 0" do
    Metrics.increment(:score, 10)
    assert Metrics.get(:score) == 10
    Metrics.reset(:score)
    assert Metrics.get(:score) == 0
    Metrics.increment(:score, 3)
    assert Metrics.get(:score) == 3
  end

  # -------------------------------------------------------
  # Gauges
  # -------------------------------------------------------

  test "gauge sets an exact value" do
    Metrics.gauge(:temp, 72)
    assert Metrics.get(:temp) == 72
  end

  test "gauge overwrites on repeated calls" do
    Metrics.gauge(:temp, 72)
    Metrics.gauge(:temp, 55)
    Metrics.gauge(:temp, 100)
    assert Metrics.get(:temp) == 100
  end

  test "gauge can decrease" do
    Metrics.gauge(:queue_depth, 50)
    Metrics.gauge(:queue_depth, 10)
    assert Metrics.get(:queue_depth) == 10
  end

  test "gauge can be set to 0" do
    Metrics.gauge(:active, 7)
    Metrics.gauge(:active, 0)
    assert Metrics.get(:active) == 0
  end

  # -------------------------------------------------------
  # get/1
  # -------------------------------------------------------

  test "get returns nil for unknown metric" do
    assert Metrics.get(:does_not_exist) == nil
  end

  # -------------------------------------------------------
  # reset/1
  # -------------------------------------------------------

  test "reset sets a gauge back to 0" do
    Metrics.gauge(:level, 99)
    Metrics.reset(:level)
    assert Metrics.get(:level) == 0
  end

  test "reset on unknown metric sets it to 0" do
    Metrics.reset(:brand_new)
    assert Metrics.get(:brand_new) == 0
  end

  # -------------------------------------------------------
  # all/0 and snapshot/0
  # -------------------------------------------------------

  test "all/0 returns a map of all metrics" do
    Metrics.increment(:a, 1)
    Metrics.gauge(:b, 42)
    result = Metrics.all()
    assert is_map(result)
    assert result[:a] == 1
    assert result[:b] == 42
  end

  test "snapshot/0 returns the same data as all/0" do
    Metrics.increment(:x, 7)
    Metrics.gauge(:y, 3)
    assert Metrics.snapshot() == Metrics.all()
  end

  test "snapshot is a point-in-time copy — mutating after doesn't change it" do
    Metrics.increment(:counter, 1)
    snap = Metrics.snapshot()
    Metrics.increment(:counter, 99)
    assert snap[:counter] == 1
    assert Metrics.get(:counter) == 100
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different metric names are completely independent" do
    Metrics.increment(:foo, 3)
    Metrics.gauge(:bar, 10)
    assert Metrics.get(:foo) == 3
    assert Metrics.get(:bar) == 10
  end

  # -------------------------------------------------------
  # Concurrent increments
  # -------------------------------------------------------

  test "100 concurrent tasks each incrementing by 1 produce a final value of 100" do
    1..100
    |> Enum.map(fn _ -> Task.async(fn -> Metrics.increment(:concurrent, 1) end) end)
    |> Task.await_many(5_000)

    assert Metrics.get(:concurrent) == 100
  end

  test "concurrent increments and gauge writes don't interfere with each other" do
    tasks =
      Enum.map(1..50, fn _ -> Task.async(fn -> Metrics.increment(:c1, 1) end) end) ++
        Enum.map(1..50, fn i -> Task.async(fn -> Metrics.gauge(:g1, i) end) end)

    Task.await_many(tasks, 5_000)

    assert Metrics.get(:c1) == 50
    assert Metrics.get(:g1) in 1..50
  end

  test "start_link registers the server under a custom :name option" do
    :ok = stop_supervised(Metrics)

    pid = start_supervised!({Metrics, name: :custom_metrics_server})

    assert Process.whereis(:custom_metrics_server) == pid
    assert :ok = Metrics.increment(:via_custom_name, 2)
    assert Metrics.get(:via_custom_name) == 2
  end

  test "increment and get still work while the owning GenServer is suspended" do
    :sys.suspend(Metrics)

    try do
      assert :ok = Metrics.increment(:hot_path, 3)
      assert :ok = Metrics.increment(:hot_path)
      assert Metrics.get(:hot_path) == 4
    after
      :sys.resume(Metrics)
    end
  end

  test "a negative increment amount never lowers an existing counter" do
    Metrics.increment(:downward, 10)

    try do
      Metrics.increment(:downward, -4)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    assert Metrics.get(:downward) >= 10
  end

  test "start_link defaults the process registration name to the module itself" do
    assert is_pid(Process.whereis(Metrics))
  end

  test "all/0 and snapshot/0 return an empty map when nothing has been recorded" do
    assert Metrics.all() == %{}
    assert Metrics.snapshot() == %{}
  end
end
