# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

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

  test "compensating a fully-succeeded nested step recurses into its own nested steps" do
    Process.put(:order, [])

    inner =
      Saga.new()
      |> Saga.step(:i1, fn _ -> {:ok, :r1} end, fn _ ->
        track(:i1)
        :ui1
      end)
      |> Saga.step(:i2, fn _ -> {:ok, :r2} end, fn _ ->
        track(:i2)
        :ui2
      end)

    middle =
      Saga.new()
      |> Saga.step(:m1, fn _ -> {:ok, :rm} end, fn _ ->
        track(:m1)
        :um1
      end)
      |> Saga.nest(:grand, inner)

    result =
      Saga.new()
      |> Saga.nest(:child, middle)
      |> Saga.step(:last, fn _ -> {:error, :late} end, fn _ -> :ulast end)
      |> Saga.execute(%{})

    assert {:error, [:last], :late, comp} = result
    # every level of the completed tree unwinds, innermost-last-first
    assert comp == [child: [grand: [i2: :ui2, i1: :ui1], m1: :um1]]
    assert order() == [:i2, :i1, :m1]
  end

  test "compensate_fn receives the accumulated context including completed results" do
    result =
      Saga.new()
      |> Saga.step(:a, fn ctx -> {:ok, ctx.seed * 2} end, fn ctx -> {:seen, ctx} end)
      |> Saga.step(:b, fn _ -> {:error, :stop} end, fn _ -> :ub end)
      |> Saga.execute(%{seed: 3})

    assert {:error, [:b], :stop, comp} = result
    assert {:seen, ctx} = comp[:a]
    assert ctx.seed == 3
    assert ctx.a == 6
  end

  test "steps after a failing leaf never have their actions invoked" do
    me = self()

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:error, :halt} end, fn _ -> :ub end)
      |> Saga.step(
        :c,
        fn _ ->
          send(me, :c_ran)
          {:ok, 3}
        end,
        fn _ -> :uc end
      )
      |> Saga.execute(%{})

    assert {:error, [:b], :halt, [a: :ua]} = result
    refute_receive :c_ran, 50
  end

  test "failing nest reports inner results first then completed outer nest and leaf" do
    first =
      Saga.new()
      |> Saga.step(:p, fn _ -> {:ok, 1} end, fn _ -> :up end)
      |> Saga.step(:q, fn _ -> {:ok, 2} end, fn _ -> :uq end)

    second =
      Saga.new()
      |> Saga.step(:r, fn _ -> {:ok, 3} end, fn _ -> :ur end)
      |> Saga.step(:s, fn _ -> {:error, :sfail} end, fn _ -> :us end)

    result =
      Saga.new()
      |> Saga.step(:top, fn _ -> {:ok, :t} end, fn _ -> :utop end)
      |> Saga.nest(:one, first)
      |> Saga.nest(:two, second)
      |> Saga.execute(%{})

    assert {:error, [:two, :s], :sfail, comp} = result
    assert comp == [two: [r: :ur], one: [q: :uq, p: :up], top: :utop]
  end

  test "a raising compensation inside a nested saga still lets sibling compensations run" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 1} end, fn _ -> :ux end)
      |> Saga.step(:y, fn _ -> {:ok, 2} end, fn _ -> raise "inner boom" end)

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, :aa} end, fn _ -> :ua end)
      |> Saga.nest(:child, sub)
      |> Saga.step(:last, fn _ -> {:error, :late} end, fn _ -> :ulast end)
      |> Saga.execute(%{})

    assert {:error, [:last], :late, comp} = result
    assert [{:child, inner}, {:a, :ua}] = comp
    assert match?({:exception, %RuntimeError{message: "inner boom"}, _}, inner[:y])
    assert inner[:x] == :ux
  end

  test "recorded compensation exception carries the raised struct and a stacktrace" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> raise ArgumentError, "kaput" end)
      |> Saga.step(:b, fn _ -> {:error, :fail} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:error, [:b], :fail, comp} = result
    assert {:exception, exception, stack} = comp[:a]
    assert %ArgumentError{message: "kaput"} = exception
    assert is_list(stack)
    assert stack != []
    assert Enum.all?(stack, &is_tuple/1)
  end

  test "a compensation returning an error tuple is recorded without changing the failure" do
    # TODO
  end

  test "a step after a nested step reads the sub-saga context under the nest name" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 7} end, fn _ -> :ux end)

    result =
      Saga.new()
      |> Saga.step(:seedy, fn _ -> {:ok, 2} end, fn _ -> :us end)
      |> Saga.nest(:child, sub)
      |> Saga.step(:total, fn ctx -> {:ok, ctx.child.x * ctx.seedy} end, fn _ -> :ut end)
      |> Saga.execute(%{})

    assert {:ok, ctx} = result
    assert ctx.total == 14
    assert ctx.child.seedy == 2
  end

  test "a fully-succeeded nest three levels deep unwinds every level in reverse" do
    Process.put(:order, [])

    great =
      Saga.new()
      |> Saga.step(:g1, fn _ -> {:ok, 1} end, fn _ ->
        track(:g1)
        :ug1
      end)
      |> Saga.step(:g2, fn _ -> {:ok, 2} end, fn _ ->
        track(:g2)
        :ug2
      end)

    grand =
      Saga.new()
      |> Saga.nest(:great, great)
      |> Saga.step(:d1, fn _ -> {:ok, 3} end, fn _ ->
        track(:d1)
        :ud1
      end)

    child =
      Saga.new()
      |> Saga.step(:c1, fn _ -> {:ok, 4} end, fn _ ->
        track(:c1)
        :uc1
      end)
      |> Saga.nest(:grand, grand)

    result =
      Saga.new()
      |> Saga.nest(:child, child)
      |> Saga.step(:boom, fn _ -> {:error, :late} end, fn _ -> :ubm end)
      |> Saga.execute(%{})

    assert {:error, [:boom], :late, comp} = result
    # each nested entry is itself a keyword list, in reverse order, at every depth
    assert comp == [child: [grand: [d1: :ud1, great: [g2: :ug2, g1: :ug1]], c1: :uc1]]
    assert order() == [:d1, :g2, :g1, :c1]
  end

  test "inner compensations of a fully-succeeded nest see the results completed before failure" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn ctx -> {:ok, ctx.seed + 1} end, fn ctx -> {:x_saw, ctx} end)
      |> Saga.step(:y, fn ctx -> {:ok, ctx.x * 2} end, fn ctx -> {:y_saw, ctx} end)

    result =
      Saga.new()
      |> Saga.step(:top, fn _ -> {:ok, :t} end, fn _ -> :utop end)
      |> Saga.nest(:child, sub)
      |> Saga.step(:last, fn _ -> {:error, :late} end, fn _ -> :ul end)
      |> Saga.execute(%{seed: 1})

    assert {:error, [:last], :late, comp} = result
    assert [{:child, inner}, {:top, :utop}] = comp
    assert {:x_saw, x_ctx} = inner[:x]
    assert {:y_saw, y_ctx} = inner[:y]
    assert x_ctx.seed == 1
    assert x_ctx.top == :t
    assert x_ctx.x == 2
    assert x_ctx.y == 4
    assert y_ctx.x == 2
    assert y_ctx.y == 4
  end

  test "compensation inside a nest of a fully-succeeded nest sees its own inner results" do
    grand =
      Saga.new()
      |> Saga.step(:g, fn ctx -> {:ok, ctx.top + 1} end, fn ctx -> {:g_saw, ctx} end)

    child =
      Saga.new()
      |> Saga.step(:m, fn _ -> {:ok, :mm} end, fn _ -> :um end)
      |> Saga.nest(:grand, grand)

    result =
      Saga.new()
      |> Saga.step(:top, fn _ -> {:ok, 1} end, fn _ -> :ut end)
      |> Saga.nest(:child, child)
      |> Saga.step(:last, fn _ -> {:error, :late} end, fn _ -> :ul end)
      |> Saga.execute(%{})

    assert {:error, [:last], :late, comp} = result
    assert [{:child, inner}, {:top, :ut}] = comp
    assert {:g_saw, g_ctx} = inner[:grand][:g]
    assert g_ctx.top == 1
    assert g_ctx.m == :mm
    assert g_ctx.g == 2
  end

  test "compensations in a failing sub-saga see outer and inner completed results" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn ctx -> {:ok, ctx.base * 2} end, fn ctx -> {:inner_saw, ctx} end)
      |> Saga.step(:y, fn _ -> {:error, :bad} end, fn _ -> :uy end)

    result =
      Saga.new()
      |> Saga.step(:base, fn _ -> {:ok, 5} end, fn ctx -> {:outer_saw, ctx} end)
      |> Saga.nest(:child, sub)
      |> Saga.execute(%{seed: :s})

    assert {:error, [:child, :y], :bad, comp} = result
    assert [{:child, inner}, {:base, outer}] = comp
    assert {:inner_saw, inner_ctx} = inner[:x]
    assert inner_ctx.seed == :s
    assert inner_ctx.base == 5
    assert inner_ctx.x == 10
    assert {:outer_saw, outer_ctx} = outer
    assert outer_ctx.seed == :s
    assert outer_ctx.base == 5
  end
end
```
