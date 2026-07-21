# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Saga do
  @moduledoc """
  Saga pattern with a **durable journal** and **crash-resumable execution**.

  Each run emits a chronological list of events — `{:completed, name, result}`,
  `{:failed, name, reason}`, `{:compensated, name, value}` — returned alongside
  the usual result. `resume/3` rebuilds state from such a journal, skipping the
  actions of steps that already completed and continuing with the rest. A
  failure during a resumed run rolls back every completed step (replayed and
  newly run alike) in reverse order.
  """

  @typedoc "An accumulated context passed to every action and compensation."
  @type context :: map()

  @typedoc "The result an action function must return."
  @type action_result :: {:ok, term()} | {:error, term()}

  @typedoc "A single named step in the saga definition."
  @type step_entry :: %{
          name: atom(),
          action: (context() -> action_result()),
          compensate: (context() -> term())
        }

  @typedoc "A single chronological journal event."
  @type event ::
          {:completed, atom(), term()}
          | {:failed, atom(), term()}
          | {:compensated, atom(), term()}

  @typedoc "An ordered, chronological list of journal events."
  @type journal :: [event()]

  @typedoc "The saga struct holding an ordered list of steps."
  @type t :: %__MODULE__{steps: [step_entry()]}

  @typedoc "The value returned by `execute/2` and `resume/3`."
  @type run_result ::
          {:ok, context(), journal()}
          | {:error, atom(), term(), keyword(), journal()}

  defstruct steps: []

  @doc "Creates a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Appends a named step."
  @spec step(t(), atom(), (context() -> action_result()), (context() -> term())) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Executes the saga from the beginning."
  @spec execute(t(), context()) :: run_result()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context, [])
  end

  @doc "Resumes execution from a previously produced journal."
  @spec resume(t(), context(), journal()) :: run_result()
  def resume(%__MODULE__{steps: steps}, context, journal)
      when is_map(context) and is_list(journal) do
    completed_names =
      for {:completed, name, _result} <- journal, do: name

    context2 =
      Enum.reduce(journal, context, fn
        {:completed, name, result}, acc -> Map.put(acc, name, result)
        _other, acc -> acc
      end)

    {done_steps, remaining} =
      Enum.split_with(steps, fn step -> step.name in completed_names end)

    # Seed the reverse-accumulator journal with the completed events so the
    # returned journal stays chronological once reversed.
    jrev0 =
      journal
      |> Enum.filter(fn
        {:completed, _n, _r} -> true
        _ -> false
      end)
      |> Enum.reverse()

    run(remaining, Enum.reverse(done_steps), context2, jrev0)
  end

  # --- execution -----------------------------------------------------------
  #
  # `completed` is in reverse-execution order (most recent first).
  # `jrev` is the journal accumulated in reverse (most recent event first).

  @spec run([step_entry()], [step_entry()], context(), journal()) :: run_result()
  defp run([], _completed, context, jrev), do: {:ok, context, Enum.reverse(jrev)}

  defp run([%{name: name, action: action} = step | rest], completed, context, jrev) do
    case safe(action, context) do
      {:ok, result} ->
        run(
          rest,
          [step | completed],
          Map.put(context, name, result),
          [{:completed, name, result} | jrev]
        )

      {:error, reason} ->
        {comp, jrev2} = compensate_all(completed, context, [{:failed, name, reason} | jrev])
        {:error, name, reason, comp, Enum.reverse(jrev2)}
    end
  end

  @spec safe((context() -> term()), context()) :: action_result()
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

  @spec compensate_all([step_entry()], context(), journal()) :: {keyword(), journal()}
  defp compensate_all(completed, context, jrev0) do
    Enum.reduce(completed, {[], jrev0}, fn %{name: name, compensate: compensate}, {acc, jrev} ->
      value = safe_compensate(compensate, context)
      {acc ++ [{name, value}], [{:compensated, name, value} | jrev]}
    end)
  end

  @spec safe_compensate((context() -> term()), context()) :: term()
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

  test "execute returns final context and a chronological journal on success" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn ctx -> {:ok, ctx.a + 1} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:ok, ctx, journal} = result
    assert ctx.a == 1 and ctx.b == 2
    assert journal == [{:completed, :a, 1}, {:completed, :b, 2}]
  end

  test "execute failure journal records completed, failed and compensated events" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:error, :boom} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:error, :b, :boom, comp, journal} = result
    assert comp == [a: :ua]

    assert journal == [
             {:completed, :a, 1},
             {:failed, :b, :boom},
             {:compensated, :a, :ua}
           ]
  end

  test "resume continues from a journal without re-running completed actions" do
    Process.put(:ran, [])
    mark = fn n -> Process.put(:ran, [n | Process.get(:ran)]) end

    saga =
      Saga.new()
      |> Saga.step(
        :a,
        fn _ ->
          mark.(:a)
          {:ok, 1}
        end,
        fn _ -> :ua end
      )
      |> Saga.step(
        :b,
        fn _ ->
          mark.(:b)
          {:ok, 2}
        end,
        fn _ -> :ub end
      )
      |> Saga.step(
        :c,
        fn ctx ->
          mark.(:c)
          {:ok, ctx.a + ctx.b}
        end,
        fn _ -> :uc end
      )

    journal = [{:completed, :a, 1}, {:completed, :b, 2}]
    result = Saga.resume(saga, %{}, journal)

    assert {:ok, ctx, jr} = result
    assert ctx.a == 1 and ctx.b == 2 and ctx.c == 3
    # Only :c actually executed during the resume.
    assert Enum.reverse(Process.get(:ran)) == [:c]

    assert jr == [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:completed, :c, 3}
           ]
  end

  test "resume compensates journaled and newly run steps in reverse on failure" do
    saga =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)
      |> Saga.step(:c, fn _ -> {:error, :late} end, fn _ -> :uc end)

    journal = [{:completed, :a, 1}]
    result = Saga.resume(saga, %{}, journal)

    assert {:error, :c, :late, comp, jr} = result
    assert comp == [b: :ub, a: :ua]

    assert jr == [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:failed, :c, :late},
             {:compensated, :b, :ub},
             {:compensated, :a, :ua}
           ]
  end

  test "resume with an empty journal behaves like execute" do
    # TODO
  end

  test "resume merges journaled results into the context for later steps" do
    saga =
      Saga.new()
      |> Saga.step(:base, fn _ -> {:ok, 10} end, fn _ -> nil end)
      |> Saga.step(:derived, fn ctx -> {:ok, ctx.base * 3} end, fn _ -> nil end)

    result = Saga.resume(saga, %{}, [{:completed, :base, 10}])
    assert {:ok, ctx, _jr} = result
    assert ctx.derived == 30
  end

  test "all compensations run even if one raises" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> raise "boom" end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, comp, _journal} = result
    assert comp[:b] == :ub
    assert match?({:exception, _, _}, comp[:a])
  end

  test "a raising compensation does not abort the compensations that follow it" do
    Process.put(:comp_order, [])
    record = fn n -> Process.put(:comp_order, [n | Process.get(:comp_order)]) end

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ ->
        record.(:a)
        :ua
      end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ ->
        record.(:b)
        raise "boom"
      end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, comp, journal} = result
    # :b's compensation raises first, so :a's compensation is the one that
    # must still run after the raise.
    assert Enum.reverse(Process.get(:comp_order)) == [:b, :a]
    assert [{:b, {:exception, %RuntimeError{}, _}}, {:a, :ua}] = comp

    assert [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:failed, :c, :fail},
             {:compensated, :b, {:exception, %RuntimeError{}, _}},
             {:compensated, :a, :ua}
           ] = journal
  end

  test "resume compensates every remaining step after a replayed step's raise" do
    Process.put(:resume_comp_order, [])
    record = fn n -> Process.put(:resume_comp_order, [n | Process.get(:resume_comp_order)]) end

    saga =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ ->
        record.(:a)
        :ua
      end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ ->
        record.(:b)
        raise "boom"
      end)
      |> Saga.step(:c, fn _ -> {:error, :late} end, fn _ -> :uc end)

    result = Saga.resume(saga, %{}, [{:completed, :a, 1}])

    assert {:error, :c, :late, comp, journal} = result
    assert Enum.reverse(Process.get(:resume_comp_order)) == [:b, :a]
    assert [{:b, {:exception, %RuntimeError{}, _}}, {:a, :ua}] = comp

    assert [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:failed, :c, :late},
             {:compensated, :b, {:exception, %RuntimeError{}, _}},
             {:compensated, :a, :ua}
           ] = journal
  end

  test "empty saga returns original context with an empty journal" do
    assert {:ok, %{x: 1}, []} = Saga.new() |> Saga.execute(%{x: 1})
  end
end
```
