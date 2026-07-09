# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DataFlowRunner do
  @moduledoc """
  A `GenServer` that accepts tasks with dependencies and executes them in a
  valid topological order, running independent tasks concurrently, while
  threading each task's dependency results into that task's one-arity function.

  Execution proceeds layer by layer: every task in a layer has all of its
  dependencies satisfied and none of the tasks in the same layer depend on one
  another, so they run in parallel. Before a task runs, the results of its
  direct dependencies are collected into a map and passed as its single argument.
  """

  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def submit(name, task_id, opts) do
    depends_on = Keyword.get(opts, :depends_on, [])

    func =
      case Keyword.fetch(opts, :func) do
        {:ok, f} when is_function(f, 1) ->
          f

        {:ok, _} ->
          raise ArgumentError, ":func must be a one-arity function"

        :error ->
          raise ArgumentError, ":func option is required"
      end

    GenServer.call(name, {:submit, task_id, depends_on, func})
  end

  def run_all(name) do
    GenServer.call(name, :run_all, :infinity)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:submit, task_id, depends_on, func}, _from, tasks) do
    {:reply, :ok, Map.put(tasks, task_id, %{depends_on: depends_on, func: func})}
  end

  def handle_call(:run_all, _from, tasks) do
    result =
      with :ok <- check_unknown_dependencies(tasks),
           {:ok, layers} <- topological_layers(tasks) do
        {:ok, execute(layers, tasks)}
      end

    {:reply, result, tasks}
  end

  # ── Validation ──────────────────────────────────────────────────────────

  defp check_unknown_dependencies(tasks) do
    known = MapSet.new(Map.keys(tasks))

    missing =
      tasks
      |> Enum.flat_map(fn {_id, %{depends_on: deps}} -> deps end)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(known, &1))

    case missing do
      [] -> :ok
      _ -> {:error, {:unknown_dependencies, missing}}
    end
  end

  # ── Topological sort (Kahn's algorithm), grouped into layers ────────────

  defp topological_layers(tasks) do
    in_degree =
      Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, length(Enum.uniq(deps))} end)

    dependents =
      Enum.reduce(tasks, %{}, fn {id, %{depends_on: deps}}, acc ->
        Enum.reduce(Enum.uniq(deps), acc, fn dep, acc2 ->
          Map.update(acc2, dep, [id], &[id | &1])
        end)
      end)

    build_layers(in_degree, dependents, [])
  end

  defp build_layers(in_degree, _dependents, layers) when map_size(in_degree) == 0 do
    {:ok, Enum.reverse(layers)}
  end

  defp build_layers(in_degree, dependents, layers) do
    ready = for {id, 0} <- in_degree, do: id

    case ready do
      [] ->
        {:error, {:cycle, Map.keys(in_degree)}}

      _ ->
        remaining = Map.drop(in_degree, ready)

        remaining =
          Enum.reduce(ready, remaining, fn id, acc ->
            dependents
            |> Map.get(id, [])
            |> Enum.reduce(acc, fn dependent, acc2 ->
              case Map.fetch(acc2, dependent) do
                {:ok, n} -> Map.put(acc2, dependent, n - 1)
                :error -> acc2
              end
            end)
          end)

        build_layers(remaining, dependents, [ready | layers])
    end
  end

  # ── Execution (data-flow: pass dependency results as input) ──────────────

  defp execute(layers, tasks) do
    Enum.reduce(layers, %{}, fn layer, results ->
      layer_results =
        layer
        |> Enum.map(fn id ->
          %{depends_on: deps, func: func} = Map.fetch!(tasks, id)
          inputs = Map.new(deps, fn d -> {d, Map.fetch!(results, d)} end)
          {id, Task.async(fn -> func.(inputs) end)}
        end)
        |> Enum.map(fn {id, task} -> {id, Task.await(task, :infinity)} end)
        |> Map.new()

      Map.merge(results, layer_results)
    end)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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
end
```
