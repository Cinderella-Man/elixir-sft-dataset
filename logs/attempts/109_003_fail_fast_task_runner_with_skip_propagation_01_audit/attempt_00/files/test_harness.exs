defmodule ResilientRunnerTest do
  use ExUnit.Case, async: false

  defmodule Recorder do
    use Agent

    def start_link(_ \\ nil) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(id, phase) do
      t = System.monotonic_time(:millisecond)
      Agent.update(__MODULE__, fn evs -> [{id, phase, t} | evs] end)
    end

    def events, do: Agent.get(__MODULE__, &Enum.reverse/1)

    def ran?(id) do
      Enum.any?(events(), fn
        {^id, :start, _} -> true
        _ -> false
      end)
    end
  end

  defp ok_task(id, sleep_ms \\ 0, ret \\ nil) do
    ret = if is_nil(ret), do: id, else: ret

    fn ->
      Recorder.record(id, :start)
      if sleep_ms > 0, do: Process.sleep(sleep_ms)
      Recorder.record(id, :end)
      ret
    end
  end

  defp fail_task(id, reason \\ :boom) do
    fn ->
      Recorder.record(id, :start)
      Recorder.record(id, :end)
      {:error, reason}
    end
  end

  defp raise_task(id) do
    fn ->
      Recorder.record(id, :start)
      raise "boom-#{id}"
    end
  end

  setup do
    start_supervised!(Recorder)
    pid = start_supervised!({ResilientRunner, name: :runner})
    %{runner: pid}
  end

  test "empty runner returns empty completed/failed/skipped" do
    assert {:ok, %{completed: %{}, failed: %{}, skipped: []}} =
             ResilientRunner.run_all(:runner)
  end

  test "all-success DAG populates completed" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, 1))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b, 0, 2))
    ResilientRunner.submit(:runner, :c, depends_on: [:a], func: ok_task(:c, 0, 3))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{a: 1, b: 2, c: 3}
    assert res.failed == %{}
    assert res.skipped == []
  end

  test "an {:error, _} return marks failure and skips dependents" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a, :db_down))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.failed == %{a: :db_down}
    assert res.skipped == [:b]
    assert res.completed == %{}
    refute Recorder.ran?(:b)
  end

  test "a raising task is captured as a failure, not re-raised" do
    ResilientRunner.submit(:runner, :a, func: raise_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert Map.has_key?(res.failed, :a)
    assert res.skipped == [:b]
    refute Recorder.ran?(:b)
  end

  test "skip propagates transitively down a chain" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))
    ResilientRunner.submit(:runner, :c, depends_on: [:b], func: ok_task(:c))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert Map.has_key?(res.failed, :a)
    assert Enum.sort(res.skipped) == [:b, :c]
    refute Recorder.ran?(:b)
    refute Recorder.ran?(:c)
  end

  test "an unrelated sibling branch still completes when another fails" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))
    ResilientRunner.submit(:runner, :x, func: ok_task(:x, 0, :x_val))
    ResilientRunner.submit(:runner, :y, depends_on: [:x], func: ok_task(:y, 0, :y_val))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{x: :x_val, y: :y_val}
    assert Map.has_key?(res.failed, :a)
    assert res.skipped == [:b]
  end

  test "diamond: one failing parent skips only the join, other parent completes" do
    #      a
    #     / \
    #    b   c    (b fails)
    #     \ /
    #      d
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: fail_task(:b))
    ResilientRunner.submit(:runner, :c, depends_on: [:a], func: ok_task(:c, 0, :c))
    ResilientRunner.submit(:runner, :d, depends_on: [:b, :c], func: ok_task(:d))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{a: :a, c: :c}
    assert Map.has_key?(res.failed, :b)
    assert res.skipped == [:d]
    refute Recorder.ran?(:d)
  end

  test "a dependent starts only after its dependency finishes" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 50))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b, 10))

    assert {:ok, _} = ResilientRunner.run_all(:runner)

    a_end =
      Enum.find_value(Recorder.events(), fn
        {:a, :end, t} -> t
        _ -> nil
      end)

    b_start =
      Enum.find_value(Recorder.events(), fn
        {:b, :start, t} -> t
        _ -> nil
      end)

    assert a_end <= b_start
  end

  test "detects a cycle and runs nothing" do
    ResilientRunner.submit(:runner, :a, depends_on: [:b], func: ok_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:error, {:cycle, involved}} = ResilientRunner.run_all(:runner)
    assert :a in involved and :b in involved
    assert Recorder.events() == []
  end

  test "reports unknown dependencies and runs nothing" do
    ResilientRunner.submit(:runner, :b, depends_on: [:ghost], func: ok_task(:b))

    assert {:error, {:unknown_dependencies, missing}} = ResilientRunner.run_all(:runner)
    assert :ghost in missing
    assert Recorder.events() == []
  end

  test "resubmitting a task overwrites its definition" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :first))
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :second))

    assert {:ok, %{completed: %{a: :second}}} = ResilientRunner.run_all(:runner)
  end

  test "a newly ready task starts while an unrelated long task is still running" do
    ResilientRunner.submit(:runner, :slow, func: ok_task(:slow, 300))
    ResilientRunner.submit(:runner, :fast, func: ok_task(:fast, 0))
    ResilientRunner.submit(:runner, :c, depends_on: [:fast], func: ok_task(:c, 0))

    assert {:ok, _} = ResilientRunner.run_all(:runner)

    slow_end =
      Enum.find_value(Recorder.events(), fn
        {:slow, :end, t} -> t
        _ -> nil
      end)

    c_start =
      Enum.find_value(Recorder.events(), fn
        {:c, :start, t} -> t
        _ -> nil
      end)

    assert c_start < slow_end
  end

  test "submitting tasks invokes no func before run_all is called" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert Recorder.events() == []
    refute Recorder.ran?(:a)

    assert {:ok, _} = ResilientRunner.run_all(:runner)
    assert Recorder.ran?(:a)
  end

  test "a throwing task is captured as a failure and its dependents are skipped" do
    thrower = fn ->
      Recorder.record(:a, :start)
      throw(:thrown_value)
    end

    ResilientRunner.submit(:runner, :a, func: thrower)
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert Map.has_key?(res.failed, :a)
    assert res.completed == %{}
    assert res.skipped == [:b]
    refute Recorder.ran?(:b)
  end

  test "resubmitting a task replaces its previous depends_on list" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b, 0, :b_val))
    ResilientRunner.submit(:runner, :b, depends_on: [], func: ok_task(:b, 0, :b_val))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{b: :b_val}
    assert res.skipped == []
    assert Recorder.ran?(:b)
  end

  test "nil and non-two-tuple error-shaped returns are stored as successes" do
    ResilientRunner.submit(:runner, :a, func: fn -> nil end)
    ResilientRunner.submit(:runner, :b, func: fn -> {:error, :too, :many} end)
    ResilientRunner.submit(:runner, :c, depends_on: [:a, :b], func: ok_task(:c, 0, :c_val))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{a: nil, b: {:error, :too, :many}, c: :c_val}
    assert res.failed == %{}
    assert res.skipped == []
  end
end
