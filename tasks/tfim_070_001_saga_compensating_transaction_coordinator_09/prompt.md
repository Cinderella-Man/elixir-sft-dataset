# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Saga do
  @moduledoc """
  Implements the Saga pattern for coordinating distributed transactions
  with automatic compensation on failure.

  ## Overview

  A saga is a sequence of named steps. Each step pairs a fallible
  *action* with an infallible *compensating action*. When any action
  fails, every action that already succeeded is compensated in reverse
  order, ensuring the system can be returned to a consistent state.

  ## Context threading

  Every action and compensating function receives the *accumulated*
  context map — the initial context merged with all results produced
  by steps that have run so far. A successful action's result is
  stored under the step's name:

      %{initial_key: value, reserve: reserve_result, charge: charge_result}

  Compensating functions receive the full context at the exact moment
  execution failed, so they have access to all data produced up to
  that point.

  ## Example

      saga =
        Saga.new()
        |> Saga.step(:reserve, &reserve_inventory/1, &release_inventory/1)
        |> Saga.step(:charge,  &charge_payment/1,   &refund_payment/1)
        |> Saga.step(:ship,    &create_shipment/1,   &cancel_shipment/1)

      case Saga.execute(saga, %{order_id: 42}) do
        {:ok, ctx} ->
          IO.inspect(ctx.ship, label: "shipment")

        {:error, failed_step, reason, compensations} ->
          IO.puts("Failed at \#{failed_step}: \#{inspect(reason)}")
          IO.inspect(compensations, label: "compensation results")
      end
  """

  @typedoc "A step stored inside the saga."
  @type step :: %{
          name: atom(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensate: (context() -> term())
        }

  @typedoc "The context map threaded through every action and compensation."
  @type context :: map()

  @typedoc "Keyword list of `[step_name: compensation_return_value]`."
  @type compensation_results :: keyword()

  @typedoc """
  Returned by `execute/2`.

    * `{:ok, final_context}` — every step succeeded.
    * `{:error, failed_step, reason, compensation_results}` — a step failed;
      all previously completed steps were compensated in reverse order.
  """
  @type execute_result ::
          {:ok, context()}
          | {:error, atom(), term(), compensation_results()}

  defstruct steps: []

  @type t :: %__MODULE__{steps: [step()]}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new, empty saga.

      iex> Saga.new()
      %Saga{steps: []}
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Appends a named step to the saga.

  ## Parameters

    * `saga`          – the saga to extend.
    * `name`          – an atom that uniquely identifies the step. The
                        step's result will be stored in the context under
                        this key.
    * `action_fn`     – `(context -> {:ok, result} | {:error, reason})`.
                        Receives the current accumulated context.
    * `compensate_fn` – `(context -> any)`. Receives the context at the
                        point of failure. Its return value is recorded but
                        never causes a failure; any exception is caught and
                        recorded instead.

  Steps are executed in the order they are added.
  """
  @spec step(
          t(),
          atom(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term())
        ) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc """
  Executes the saga against an initial `context` map.

  Steps run strictly in the order they were added. Each successful
  step merges its result into the context under the step's name before
  the next step begins.

  On failure the compensating functions for all *completed* steps run
  in **reverse order**. Failures (or exceptions) inside a compensating
  function are caught, recorded, and never abort the remaining
  compensations.

  ## Return values

    * `{:ok, final_context}` — all steps succeeded.
    * `{:error, failed_step_name, reason, compensation_results}` — the
      step named `failed_step_name` returned `{:error, reason}`. The
      `compensation_results` keyword list contains one entry per
      compensated step, in reverse execution order.
  """
  @spec execute(t(), context()) :: execute_result()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run_steps(steps, [], context)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # No more steps — full success.
  @spec run_steps([step()], [step()], context()) :: execute_result()
  defp run_steps([], _completed, context), do: {:ok, context}

  defp run_steps(
         [%{name: name, action: action} = step | rest],
         completed,
         context
       ) do
    case safe_action(action, context) do
      {:ok, result} ->
        enriched = Map.put(context, name, result)
        run_steps(rest, [step | completed], enriched)

      {:error, reason} ->
        # `completed` is already in reverse-execution order (most recent first)
        compensation_results = compensate_all(completed, context)
        {:error, name, reason, compensation_results}
    end
  end

  # Runs the action and normalises any unexpected return into an error.
  @spec safe_action((context() -> term()), context()) :: {:ok, term()} | {:error, term()}
  defp safe_action(action, context) do
    case action.(context) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
  end

  # Runs all compensations in order (which is already reverse-execution order)
  # and collects their results. Exceptions are caught and stored.
  @spec compensate_all([step()], context()) :: compensation_results()
  defp compensate_all(completed_steps, context) do
    Enum.map(completed_steps, fn %{name: name, compensate: compensate} ->
      result =
        try do
          compensate.(context)
        rescue
          exception -> {:exception, exception, __STACKTRACE__}
        catch
          kind, value -> {:caught, kind, value}
        end

      {name, result}
    end)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SagaTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers — tracked side-effects via the process dictionary so tests remain
  # purely functional without needing extra processes.
  # ---------------------------------------------------------------------------

  defp track(key, value) do
    existing = Process.get(key, [])
    Process.put(key, existing ++ [value])
  end

  defp tracked(key), do: Process.get(key, [])

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  test "executes all steps and returns enriched context on success" do
    result =
      Saga.new()
      |> Saga.step(:reserve, fn ctx -> {:ok, "reservation:#{ctx.user}"} end, fn _ctx ->
        :cancel
      end)
      |> Saga.step(:charge, fn ctx -> {:ok, "charge:#{ctx.reserve}"} end, fn _ctx -> :refund end)
      |> Saga.step(:notify, fn ctx -> {:ok, "notified:#{ctx.charge}"} end, fn _ctx ->
        :undo_notify
      end)
      |> Saga.execute(%{user: "alice"})

    assert {:ok, ctx} = result
    assert ctx.reserve == "reservation:alice"
    assert ctx.charge == "charge:reservation:alice"
    assert ctx.notify == "notified:charge:reservation:alice"
  end

  test "happy path calls no compensations" do
    Saga.new()
    |> Saga.step(
      :a,
      fn _ctx -> {:ok, :done} end,
      fn _ctx -> track(:compensated, :a) end
    )
    |> Saga.execute(%{})

    assert tracked(:compensated) == []
  end

  # ---------------------------------------------------------------------------
  # Failure & compensation
  # ---------------------------------------------------------------------------

  test "returns error tuple when a step fails" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, 1} end, fn _ctx -> nil end)
      |> Saga.step(:b, fn _ctx -> {:error, :boom} end, fn _ctx -> nil end)
      |> Saga.step(:c, fn _ctx -> {:ok, 3} end, fn _ctx -> nil end)
      |> Saga.execute(%{})

    assert {:error, :b, :boom, _compensation_results} = result
  end

  test "compensations run in reverse order when step 2 of 3 fails" do
    Saga.new()
    |> Saga.step(
      :reserve,
      fn _ctx -> {:ok, :reserved} end,
      fn _ctx -> track(:comp_order, :reserve) end
    )
    |> Saga.step(
      :charge,
      fn _ctx -> {:error, :card_declined} end,
      fn _ctx -> track(:comp_order, :charge) end
    )
    |> Saga.step(
      :notify,
      fn _ctx -> {:ok, :notified} end,
      fn _ctx -> track(:comp_order, :notify) end
    )
    |> Saga.execute(%{})

    # :charge never succeeded, so only :reserve should be compensated
    # :notify never ran, so it should not be compensated
    assert tracked(:comp_order) == [:reserve]
  end

  test "compensation results are included in the error tuple, in reverse order" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, :a_ok} end, fn _ctx -> :a_compensated end)
      |> Saga.step(:b, fn _ctx -> {:ok, :b_ok} end, fn _ctx -> :b_compensated end)
      |> Saga.step(:c, fn _ctx -> {:error, :c_failed} end, fn _ctx -> :c_compensated end)
      |> Saga.execute(%{})

    assert {:error, :c, :c_failed, comp} = result
    assert comp == [b: :b_compensated, a: :a_compensated]
  end

  test "failed step receives context enriched by prior successful steps" do
    Saga.new()
    |> Saga.step(:first, fn _ctx -> {:ok, 42} end, fn _ctx -> nil end)
    |> Saga.step(
      :second,
      fn ctx ->
        track(:saw_context, ctx)
        {:error, :oops}
      end,
      fn _ctx -> nil end
    )
    |> Saga.execute(%{initial: true})

    [ctx] = tracked(:saw_context)
    assert ctx.initial == true
    assert ctx.first == 42
  end

  test "compensations receive the enriched context at the point of failure" do
    Saga.new()
    |> Saga.step(:step_a, fn _ctx -> {:ok, :a_result} end, fn ctx ->
      track(:comp_ctx, ctx)
    end)
    |> Saga.step(:step_b, fn _ctx -> {:error, :fail} end, fn _ctx -> nil end)
    |> Saga.execute(%{seed: :value})

    [ctx] = tracked(:comp_ctx)
    # Context should include original seed and the result of step_a
    assert ctx.seed == :value
    assert ctx.step_a == :a_result
  end

  # ---------------------------------------------------------------------------
  # Compensation resilience
  # ---------------------------------------------------------------------------

  test "all compensations run even if one raises an exception" do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "empty saga returns the original context unchanged" do
    assert {:ok, %{x: 1}} = Saga.new() |> Saga.execute(%{x: 1})
  end

  test "first step failing runs no compensations" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:error, :immediate} end, fn _ctx ->
        track(:comp, :a)
      end)
      |> Saga.execute(%{})

    assert {:error, :a, :immediate, []} = result
    assert tracked(:comp) == []
  end

  test "single successful step returns context with its result" do
    assert {:ok, %{only: :result}} =
             Saga.new()
             |> Saga.step(:only, fn _ctx -> {:ok, :result} end, fn _ctx -> nil end)
             |> Saga.execute(%{})
  end
end
```
