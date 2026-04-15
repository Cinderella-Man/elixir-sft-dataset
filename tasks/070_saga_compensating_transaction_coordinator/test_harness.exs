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
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, :ok} end, fn _ctx ->
        track(:ran, :a)
        raise "oops from compensation A"
      end)
      |> Saga.step(:b, fn _ctx -> {:ok, :ok} end, fn _ctx ->
        track(:ran, :b)
      end)
      |> Saga.step(:c, fn _ctx -> {:error, :fail} end, fn _ctx ->
        track(:ran, :c)
      end)
      |> Saga.execute(%{})

    # Both a and b should have been compensated despite a raising
    assert :b in tracked(:ran)
    assert :a in tracked(:ran)
    # The overall result is still an error tuple
    assert {:error, :c, :fail, _} = result
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
