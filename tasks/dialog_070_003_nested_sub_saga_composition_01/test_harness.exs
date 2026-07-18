defmodule SagaTest do
  use ExUnit.Case, async: false

  defp track(tag), do: Process.put(:order, [tag | Process.get(:order, [])])
  defp order, do: Process.get(:order, []) |> Enum.reverse()

  test "nested sub-saga success stores the sub-context under the step name" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 1} end, fn _ -> :ux end)
      |> Saga.step(:y, fn ctx -> {:ok, ctx.x + 1} end, fn _ -> :uy end)

    result =
      Saga.new()
      |> Saga.step(:before, fn _ -> {:ok, :b} end, fn _ -> :ub end)
      |> Saga.nest(:child, sub)
      |> Saga.execute(%{seed: 0})

    assert {:ok, ctx} = result
    assert ctx.before == :b
    assert ctx.child.x == 1
    assert ctx.child.y == 2
  end

  test "failure inside a sub-saga compensates inner then outer; path reflects nesting" do
    Process.put(:order, [])

    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 1} end, fn _ ->
        track(:sub_x)
        :ux
      end)
      |> Saga.step(:y, fn _ -> {:error, :bad} end, fn _ ->
        track(:sub_y)
        :uy
      end)

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, :aa} end, fn _ ->
        track(:a)
        :ua
      end)
      |> Saga.nest(:child, sub)
      |> Saga.step(:c, fn _ -> {:ok, :cc} end, fn _ ->
        track(:c)
        :uc
      end)
      |> Saga.execute(%{})

    assert {:error, [:child, :y], :bad, comp} = result
    assert comp == [child: [x: :ux], a: :ua]
    # :y never completed so it is not compensated; :c never ran
    assert order() == [:sub_x, :a]
  end

  test "a later outer failure fully compensates a completed nested sub-saga in reverse" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 1} end, fn _ -> :ux end)
      |> Saga.step(:y, fn _ -> {:ok, 2} end, fn _ -> :uy end)

    result =
      Saga.new()
      |> Saga.nest(:child, sub)
      |> Saga.step(:c, fn _ -> {:error, :boom} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, [:c], :boom, comp} = result
    assert comp == [child: [y: :uy, x: :ux]]
  end

  test "deeply nested sagas propagate the full failure path" do
    inner =
      Saga.new()
      |> Saga.step(:deep, fn _ -> {:error, :deep_fail} end, fn _ -> :ud end)

    middle =
      Saga.new()
      |> Saga.nest(:inner, inner)

    result =
      Saga.new()
      |> Saga.nest(:middle, middle)
      |> Saga.execute(%{})

    assert {:error, [:middle, :inner, :deep], :deep_fail, comp} = result
    # nothing completed anywhere, so nested compensation lists are empty
    assert comp == [middle: [inner: []]]
  end

  test "top-level leaf failure yields a single-element path" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:error, :nope} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:error, [:b], :nope, [a: :ua]} = result
  end

  test "raising compensation is caught and recorded, others still run" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> raise "boom" end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, [:c], :fail, comp} = result
    assert comp[:b] == :ub
    assert match?({:exception, _, _}, comp[:a])
  end

  test "sub-saga can read outer context values" do
    sub =
      Saga.new()
      |> Saga.step(:derived, fn ctx -> {:ok, ctx.base * 10} end, fn _ -> nil end)

    result =
      Saga.new()
      |> Saga.step(:base, fn _ -> {:ok, 5} end, fn _ -> nil end)
      |> Saga.nest(:child, sub)
      |> Saga.execute(%{})

    assert {:ok, ctx} = result
    assert ctx.child.derived == 50
  end

  test "empty saga returns the original context" do
    assert {:ok, %{x: 1}} = Saga.new() |> Saga.execute(%{x: 1})
  end
end
