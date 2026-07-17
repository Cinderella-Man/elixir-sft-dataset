defmodule DataFlowRunnerTest do
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

    def time(id, phase) do
      events()
      |> Enum.find_value(fn
        {^id, ^phase, t} -> t
        _ -> nil
      end)
    end

    def started_at(id), do: time(id, :start)
    def ended_at(id), do: time(id, :end)
  end

  # Wraps a one-arity function so it records its lifecycle and optionally sleeps.
  defp rec(id, sleep_ms, fun) do
    fn inputs ->
      Recorder.record(id, :start)
      if sleep_ms > 0, do: Process.sleep(sleep_ms)
      Recorder.record(id, :end)
      fun.(inputs)
    end
  end

  setup do
    start_supervised!(Recorder)
    pid = start_supervised!({DataFlowRunner, name: :runner})
    %{runner: pid}
  end

  test "empty runner returns an empty result map" do
    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{}
  end

  test "a task with no dependencies receives an empty input map" do
    assert :ok =
             DataFlowRunner.submit(:runner, :a, func: fn inputs -> {:got, map_size(inputs)} end)

    assert {:ok, %{a: {:got, 0}}} = DataFlowRunner.run_all(:runner)
  end

  test "a dependent task receives its dependency's result" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 10 end)
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: fn %{a: v} -> v + 5 end)

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{a: 10, b: 15}
  end

  test "a task with multiple deps receives all of their results" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, func: fn _ -> 2 end)

    DataFlowRunner.submit(:runner, :c,
      depends_on: [:a, :b],
      func: fn inputs -> inputs end
    )

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results.c == %{a: 1, b: 2}
  end

  test "data flows through a diamond DAG" do
    #      a
    #     / \
    #    b   c
    #     \ /
    #      d
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: fn %{a: v} -> v * 2 end)
    DataFlowRunner.submit(:runner, :c, depends_on: [:a], func: fn %{a: v} -> v * 3 end)

    DataFlowRunner.submit(:runner, :d,
      depends_on: [:b, :c],
      func: fn %{b: b, c: c} -> b + c end
    )

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{a: 1, b: 2, c: 3, d: 5}
  end

  test "a long chain accumulates results in order" do
    DataFlowRunner.submit(:runner, :t1, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :t2, depends_on: [:t1], func: fn %{t1: v} -> v + 1 end)
    DataFlowRunner.submit(:runner, :t3, depends_on: [:t2], func: fn %{t2: v} -> v + 1 end)
    DataFlowRunner.submit(:runner, :t4, depends_on: [:t3], func: fn %{t3: v} -> v + 1 end)

    assert {:ok, %{t1: 1, t2: 2, t3: 3, t4: 4}} = DataFlowRunner.run_all(:runner)
  end

  test "a dependent task starts only after its dependency finished" do
    DataFlowRunner.submit(:runner, :a, func: rec(:a, 50, fn _ -> 1 end))
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: rec(:b, 10, fn %{a: v} -> v end))

    assert {:ok, _} = DataFlowRunner.run_all(:runner)
    assert Recorder.ended_at(:a) <= Recorder.started_at(:b)
  end

  test "independent sibling tasks overlap in time" do
    DataFlowRunner.submit(:runner, :a, func: rec(:a, 40, fn _ -> 0 end))
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: rec(:b, 150, fn _ -> :b end))
    DataFlowRunner.submit(:runner, :c, depends_on: [:a], func: rec(:c, 150, fn _ -> :c end))

    assert {:ok, _} = DataFlowRunner.run_all(:runner)
    assert Recorder.started_at(:b) < Recorder.ended_at(:c)
    assert Recorder.started_at(:c) < Recorder.ended_at(:b)
  end

  test "detects a cycle and runs nothing" do
    DataFlowRunner.submit(:runner, :a, depends_on: [:b], func: rec(:a, 0, fn _ -> 1 end))
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: rec(:b, 0, fn _ -> 2 end))

    assert {:error, {:cycle, involved}} = DataFlowRunner.run_all(:runner)
    assert :a in involved and :b in involved
    assert Recorder.events() == []
  end

  test "a self-dependency is a cycle" do
    DataFlowRunner.submit(:runner, :a, depends_on: [:a], func: fn _ -> 1 end)
    assert {:error, {:cycle, _}} = DataFlowRunner.run_all(:runner)
  end

  test "reports unknown dependencies and runs nothing" do
    DataFlowRunner.submit(:runner, :real, func: rec(:real, 0, fn _ -> :ok end))
    DataFlowRunner.submit(:runner, :b, depends_on: [:ghost], func: rec(:b, 0, fn _ -> :ok end))

    assert {:error, {:unknown_dependencies, missing}} = DataFlowRunner.run_all(:runner)
    assert :ghost in missing
    assert Recorder.events() == []
  end

  test "resubmitting a task overwrites its definition" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> :first end)
    DataFlowRunner.submit(:runner, :a, func: fn _ -> :second end)

    assert {:ok, %{a: :second}} = DataFlowRunner.run_all(:runner)
  end

  test "a non-one-arity func raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      DataFlowRunner.submit(:runner, :a, func: fn -> :zero end)
    end
  end

  test "submitting alone executes nothing before run_all is called" do
    DataFlowRunner.submit(:runner, :s1, func: rec(:s1, 0, fn _ -> 1 end))

    DataFlowRunner.submit(:runner, :s2,
      depends_on: [:s1],
      func: rec(:s2, 0, fn %{s1: v} -> v end)
    )

    assert Recorder.events() == []

    assert {:ok, %{s1: 1, s2: 1}} = DataFlowRunner.run_all(:runner)
    assert Recorder.started_at(:s1) != nil
  end

  test "cycle report lists only the tasks participating in the cycle" do
    DataFlowRunner.submit(:runner, :a, depends_on: [:b], func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: fn _ -> 2 end)
    DataFlowRunner.submit(:runner, :downstream, depends_on: [:a], func: fn _ -> 3 end)

    assert {:error, {:cycle, involved}} = DataFlowRunner.run_all(:runner)
    assert Enum.sort(involved) == [:a, :b]
  end

  test "input map excludes results of tasks that were not declared as dependencies" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, func: fn _ -> 2 end)
    DataFlowRunner.submit(:runner, :c, depends_on: [:a], func: fn inputs -> inputs end)

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results.c == %{a: 1}
  end

  test "a cycle prevents an otherwise runnable independent task from executing" do
    DataFlowRunner.submit(:runner, :x, depends_on: [:y], func: rec(:x, 0, fn _ -> 1 end))
    DataFlowRunner.submit(:runner, :y, depends_on: [:x], func: rec(:y, 0, fn _ -> 2 end))
    DataFlowRunner.submit(:runner, :free, func: rec(:free, 0, fn _ -> :ran end))

    assert {:error, {:cycle, _}} = DataFlowRunner.run_all(:runner)
    assert Recorder.events() == []
    assert Recorder.started_at(:free) == nil
  end

  test "resubmitting replaces the previous dependency list, not just the func" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, depends_on: [:a, :ghost], func: fn _ -> :old end)
    DataFlowRunner.submit(:runner, :b, func: fn inputs -> {:new, inputs} end)

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{a: 1, b: {:new, %{}}}
  end

  test "non-atom task ids such as strings and tuples are supported" do
    DataFlowRunner.submit(:runner, "src", func: fn _ -> 7 end)

    DataFlowRunner.submit(:runner, {:sink, 1},
      depends_on: ["src"],
      func: fn inputs -> Map.fetch!(inputs, "src") * 2 end
    )

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{"src" => 7, {:sink, 1} => 14}
  end
end
