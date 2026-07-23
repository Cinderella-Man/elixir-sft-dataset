# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule ResilientRunner do
  @moduledoc """
  A `GenServer` that accepts tasks with dependencies and executes them in a valid
  topological order, running independent ready tasks concurrently, while
  containing failures: a task that returns `{:error, reason}` or raises/throws is
  recorded as failed (never re-raised), and every task that transitively depends
  on it is skipped. Sibling branches that don't depend on the failed task still
  run to completion.
  """

  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @spec submit(GenServer.server(), term(), keyword()) :: :ok | {:error, atom()}
  @doc "Submits `task_id` with its dependencies/opts to runner `name`. Returns `:ok`."
  def submit(name, task_id, opts) do
    depends_on = Keyword.get(opts, :depends_on, [])

    func =
      case Keyword.fetch(opts, :func) do
        {:ok, f} when is_function(f, 0) -> f
        {:ok, _} -> raise ArgumentError, ":func must be a zero-arity function"
        :error -> raise ArgumentError, ":func option is required"
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

  # ── Execution with failure containment ──────────────────────────────────

  defp execute(layers, tasks) do
    init = %{completed: %{}, failed: %{}, skipped: MapSet.new()}

    final =
      Enum.reduce(layers, init, fn layer, acc ->
        {to_skip, to_run} =
          Enum.split_with(layer, fn id ->
            %{depends_on: deps} = Map.fetch!(tasks, id)

            Enum.any?(deps, fn d ->
              Map.has_key?(acc.failed, d) or MapSet.member?(acc.skipped, d)
            end)
          end)

        acc =
          Enum.reduce(to_skip, acc, fn id, a ->
            %{a | skipped: MapSet.put(a.skipped, id)}
          end)

        to_run
        |> Enum.map(fn id ->
          %{func: func} = Map.fetch!(tasks, id)
          {id, Task.async(fn -> run_task(func) end)}
        end)
        |> Enum.map(fn {id, task} -> {id, Task.await(task, :infinity)} end)
        |> Enum.reduce(acc, fn {id, outcome}, a ->
          case outcome do
            {:ok, value} -> %{a | completed: Map.put(a.completed, id, value)}
            {:failed, reason} -> %{a | failed: Map.put(a.failed, id, reason)}
          end
        end)
      end)

    %{final | skipped: MapSet.to_list(final.skipped)}
  end

  defp run_task(func) do
    try do
      case func.() do
        {:error, reason} -> {:failed, reason}
        other -> {:ok, other}
      end
    rescue
      e -> {:failed, {:exception, e}}
    catch
      kind, value -> {:failed, {kind, value}}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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

  # A task that announces itself and then blocks until the test releases it.
  # Two such tasks can only both announce if they are in flight at the same
  # moment; a runner that finishes one task before starting the next can never
  # produce the second announcement while the first is still blocked.
  defp gate_task(id, test_pid, ret) do
    fn ->
      Recorder.record(id, :start)
      send(test_pid, {:running, id, self()})

      result =
        receive do
          :release -> ret
        after
          5_000 -> {:error, :never_released}
        end

      Recorder.record(id, :end)
      result
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
    # TODO
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

  test "two independent tasks are in flight at the same time" do
    me = self()
    ResilientRunner.submit(:runner, :p, func: gate_task(:p, me, :p_val))
    ResilientRunner.submit(:runner, :q, func: gate_task(:q, me, :q_val))

    run = Task.async(fn -> ResilientRunner.run_all(:runner) end)

    # Both must announce while neither has been released: a runner that
    # executes independent tasks one after the other cannot get here.
    assert_receive {:running, first_id, first_pid}, 2_000
    assert_receive {:running, second_id, second_pid}, 2_000
    assert Enum.sort([first_id, second_id]) == [:p, :q]

    send(first_pid, :release)
    send(second_pid, :release)

    assert {:ok, res} = Task.await(run, 5_000)
    assert res.completed == %{p: :p_val, q: :q_val}
    assert res.failed == %{}
    assert res.skipped == []
  end

  test "siblings sharing a dependency are in flight at the same time" do
    me = self()
    ResilientRunner.submit(:runner, :root, func: ok_task(:root, 0, :root_val))
    ResilientRunner.submit(:runner, :b, depends_on: [:root], func: gate_task(:b, me, :b_val))
    ResilientRunner.submit(:runner, :c, depends_on: [:root], func: gate_task(:c, me, :c_val))

    run = Task.async(fn -> ResilientRunner.run_all(:runner) end)

    # Once their shared dependency has finished, both dependents become ready
    # and must overlap rather than take turns.
    assert_receive {:running, first_id, first_pid}, 2_000
    assert_receive {:running, second_id, second_pid}, 2_000
    assert Enum.sort([first_id, second_id]) == [:b, :c]

    send(first_pid, :release)
    send(second_pid, :release)

    assert {:ok, res} = Task.await(run, 5_000)
    assert res.completed == %{root: :root_val, b: :b_val, c: :c_val}
    assert res.failed == %{}
    assert res.skipped == []
  end
end
```
