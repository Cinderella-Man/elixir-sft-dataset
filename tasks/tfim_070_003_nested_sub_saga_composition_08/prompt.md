# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Saga do
  @moduledoc """
  Saga pattern with **composable, nested sub-sagas**.

  A step is either a leaf (an action/compensation pair) or a nested step
  whose behaviour is another `Saga`. Execution and compensation both recurse
  through the resulting tree. Failures carry a `failed_path` describing the
  chain of names from the outermost saga down to the failing leaf.
  """

  defstruct steps: []

  @type t :: %__MODULE__{steps: [map()]}
  @type context :: map()
  @type action_fn :: (context() -> {:ok, term()} | {:error, term()})
  @type compensate_fn :: (context() -> term())
  @type failure :: {:error, [atom()], term(), keyword()}

  @doc "Creates a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Appends a leaf step."
  @spec step(t(), atom(), action_fn(), compensate_fn()) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{kind: :leaf, name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Appends a nested step whose behaviour is another saga."
  @spec nest(t(), atom(), t()) :: t()
  def nest(%__MODULE__{} = saga, name, %__MODULE__{} = sub_saga) when is_atom(name) do
    entry = %{kind: :nested, name: name, saga: sub_saga}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Executes the saga against an initial context map."
  @spec execute(t(), context()) :: {:ok, context()} | failure()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context)
  end

  # --- execution -----------------------------------------------------------

  defp run([], _completed, context), do: {:ok, context}

  defp run(
         [%{kind: :leaf, name: name, action: action, compensate: comp} | rest],
         completed,
         ctx
       ) do
    case safe(action, ctx) do
      {:ok, result} ->
        done = %{kind: :leaf, name: name, compensate: comp}
        run(rest, [done | completed], Map.put(ctx, name, result))

      {:error, reason} ->
        {:error, [name], reason, compensate_all(completed, ctx)}
    end
  end

  defp run([%{kind: :nested, name: name, saga: sub} | rest], completed, ctx) do
    case execute(sub, ctx) do
      {:ok, sub_ctx} ->
        done = %{kind: :nested, name: name, saga: sub, ctx: sub_ctx}
        run(rest, [done | completed], Map.put(ctx, name, sub_ctx))

      {:error, sub_path, reason, sub_comp} ->
        # The sub-saga already unwound its own completed steps; propagate and
        # then compensate this saga's previously completed steps.
        outer = compensate_all(completed, ctx)
        {:error, [name | sub_path], reason, [{name, sub_comp} | outer]}
    end
  end

  defp safe(action, context) do
    case action.(context) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
  end

  # --- compensation --------------------------------------------------------

  # `completed` is in reverse-execution order (most recent first).
  defp compensate_all(completed, ctx) do
    Enum.map(completed, fn
      %{kind: :leaf, name: name, compensate: comp} ->
        {name, safe_compensate(comp, ctx)}

      %{kind: :nested, name: name, saga: sub, ctx: sub_ctx} ->
        {name, compensate_full(sub.steps, sub_ctx)}
    end)
  end

  # Compensates a fully-succeeded saga: every step, in reverse order.
  defp compensate_full(steps, ctx) do
    steps
    |> Enum.reverse()
    |> Enum.map(fn
      %{kind: :leaf, name: name, compensate: comp} ->
        {name, safe_compensate(comp, ctx)}

      %{kind: :nested, name: name, saga: sub} ->
        {name, compensate_full(sub.steps, Map.get(ctx, name, ctx))}
    end)
  end

  defp safe_compensate(compensate, context) do
    compensate.(context)
  rescue
    exception -> {:exception, exception, __STACKTRACE__}
  catch
    kind, value -> {:caught, kind, value}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
  end

  test "empty saga returns the original context" do
    assert {:ok, %{x: 1}} = Saga.new() |> Saga.execute(%{x: 1})
  end
end
```
