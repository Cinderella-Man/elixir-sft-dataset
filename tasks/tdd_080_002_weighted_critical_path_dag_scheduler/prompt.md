# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule WeightedDAGTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp valid_topological_order?(ordering, edges) do
    index = ordering |> Enum.with_index() |> Map.new()

    Enum.all?(edges, fn {from, to} ->
      Map.fetch!(index, from) < Map.fetch!(index, to)
    end)
  end

  defp build(tasks, deps) do
    dag =
      Enum.reduce(tasks, WeightedDAG.new(), fn {id, dur}, acc ->
        WeightedDAG.add_task(acc, id, dur)
      end)

    Enum.reduce(deps, dag, fn {from, to}, acc ->
      {:ok, updated} = WeightedDAG.add_dependency(acc, from, to)
      updated
    end)
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "empty graph: sort, makespan, critical path" do
    dag = WeightedDAG.new()
    assert {:ok, []} = WeightedDAG.topological_sort(dag)
    assert {:ok, 0} = WeightedDAG.makespan(dag)
    assert {:ok, []} = WeightedDAG.critical_path(dag)
  end

  test "add_task/3 ignores duplicates and keeps original duration" do
    dag =
      WeightedDAG.new()
      |> WeightedDAG.add_task(:a, 5)
      |> WeightedDAG.add_task(:a, 99)

    {:ok, ef} = WeightedDAG.earliest_finish(dag)
    assert ef == %{a: 5}
  end

  # -------------------------------------------------------
  # Cycle detection
  # -------------------------------------------------------

  test "direct cycle is rejected eagerly" do
    dag = build([{:a, 1}, {:b, 1}], [{:a, :b}])
    assert {:error, :cycle} = WeightedDAG.add_dependency(dag, :b, :a)
  end

  test "indirect cycle is rejected" do
    dag = build([{:a, 1}, {:b, 1}, {:c, 1}], [{:a, :b}, {:b, :c}])
    assert {:error, :cycle} = WeightedDAG.add_dependency(dag, :c, :a)
  end

  # -------------------------------------------------------
  # Scheduling: linear chain
  # -------------------------------------------------------

  test "linear chain earliest start / finish / makespan / critical path" do
    dag = build([{:a, 3}, {:b, 2}, {:c, 4}], [{:a, :b}, {:b, :c}])

    assert {:ok, est} = WeightedDAG.earliest_start(dag)
    assert est == %{a: 0, b: 3, c: 5}

    assert {:ok, eft} = WeightedDAG.earliest_finish(dag)
    assert eft == %{a: 3, b: 5, c: 9}

    assert {:ok, 9} = WeightedDAG.makespan(dag)
    assert {:ok, [:a, :b, :c]} = WeightedDAG.critical_path(dag)
  end

  # -------------------------------------------------------
  # Scheduling: diamond
  # -------------------------------------------------------

  test "diamond graph picks the heavier branch as critical path" do
    #        a(3)
    #       /    \
    #    b(2)    c(5)
    #       \    /
    #        d(1)
    dag =
      build(
        [{:a, 3}, {:b, 2}, {:c, 5}, {:d, 1}],
        [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
      )

    assert {:ok, est} = WeightedDAG.earliest_start(dag)
    assert est == %{a: 0, b: 3, c: 3, d: 8}

    assert {:ok, 9} = WeightedDAG.makespan(dag)
    assert {:ok, [:a, :c, :d]} = WeightedDAG.critical_path(dag)
  end

  test "topological sort remains valid on the diamond" do
    edges = [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
    dag = build([{:a, 3}, {:b, 2}, {:c, 5}, {:d, 1}], edges)

    assert {:ok, order} = WeightedDAG.topological_sort(dag)
    assert valid_topological_order?(order, edges)
    assert length(order) == 4
  end

  # -------------------------------------------------------
  # Isolated tasks
  # -------------------------------------------------------

  test "isolated task participates in makespan" do
    dag = build([{:a, 2}, {:iso, 10}, {:b, 3}], [{:a, :b}])

    assert {:ok, order} = WeightedDAG.topological_sort(dag)
    assert :iso in order
    assert {:ok, 10} = WeightedDAG.makespan(dag)
    assert {:ok, [:iso]} = WeightedDAG.critical_path(dag)
  end

  # -------------------------------------------------------
  # Neighbours
  # -------------------------------------------------------

  test "predecessors and successors" do
    dag = build([{:a, 1}, {:b, 1}, {:c, 1}], [{:a, :c}, {:b, :c}])

    assert Enum.sort(WeightedDAG.predecessors(dag, :c)) == [:a, :b]
    assert WeightedDAG.successors(dag, :a) == [:c]
    assert WeightedDAG.successors(dag, :c) == []
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
