defmodule PolicySagaTest do
  use ExUnit.Case, async: false

  defmodule Recorder do
    use Agent

    def start_link(_ \\ nil), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(event), do: Agent.update(__MODULE__, &[event | &1])
    def events, do: Agent.get(__MODULE__, &Enum.reverse(&1))
    def comps, do: Enum.filter(events(), &match?({:comp, _}, &1))
  end

  setup do
    start_supervised!(Recorder)
    :ok
  end

  defp ok_action(name, result) do
    fn _ctx ->
      Recorder.record({:action, name})
      {:ok, result}
    end
  end

  defp fail_action(name, reason) do
    fn _ctx ->
      Recorder.record({:action, name})
      {:error, reason}
    end
  end

  defp comp(name, ret \\ {:ok, :compensated}) do
    fn _ctx ->
      Recorder.record({:comp, name})
      ret
    end
  end

  # ------------------------------------------------------------------

  test "happy path: all steps succeed, no compensation" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b))

    assert {:ok, %{a: 1, b: 2}} = PolicySaga.execute(saga, %{})
    assert Recorder.comps() == []
  end

  test "failure with all compensations succeeding: no abort" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b))
      |> PolicySaga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.step == :c
    assert err.error == :boom
    assert err.compensated == [:b, :a]
    assert err.aborted_at == nil
    assert err.uncompensated == []
    assert Recorder.comps() == [{:comp, :b}, {:comp, :a}]
  end

  test ":continue policy keeps rolling back past a failed compensation" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a, {:ok, :undo_a}))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed}),
        on_error: :continue
      )
      |> PolicySaga.step(:c, fail_action(:c, :nope), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}
    assert err.aborted_at == nil
    assert err.uncompensated == []
  end

  test ":abort policy stops the rollback and leaves earlier steps uncompensated" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed}), on_error: :abort)
      |> PolicySaga.step(:c, ok_action(:c, 3), comp(:c))
      |> PolicySaga.step(:d, fail_action(:d, :fail), comp(:d))

    assert {:error, err} = PolicySaga.execute(saga, %{})

    assert err.step == :d
    # Reverse completion order is c, b, a. c runs (ok), b runs (error → abort).
    assert err.compensated == [:c, :b]
    assert err.compensations == %{c: {:ok, :compensated}, b: {:error, :undo_failed}}
    assert err.aborted_at == :b
    assert err.uncompensated == [:a]

    # a's compensation must NOT have run.
    assert Recorder.comps() == [{:comp, :c}, {:comp, :b}]
  end

  test ":abort policy does not fire when that step's compensation succeeds" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b, {:ok, :fine}), on_error: :abort)
      |> PolicySaga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.aborted_at == nil
    assert err.uncompensated == []
  end

  test "first step failing runs no compensations" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, fail_action(:a, :boom), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.step == :a
    assert err.compensated == []
    assert err.compensations == %{}
    assert err.aborted_at == nil
    assert err.uncompensated == []
    assert Recorder.comps() == []
  end

  test "a compensation sees its own step's stored result" do
    reserve = fn _ -> {:ok, %{reservation_id: "abc"}} end

    cancel = fn ctx ->
      Recorder.record({:comp_ctx, ctx[:reserve]})
      {:ok, :cancelled}
    end

    saga =
      PolicySaga.new()
      |> PolicySaga.step(:reserve, reserve, cancel)
      |> PolicySaga.step(:charge, fail_action(:charge, :declined), comp(:charge))

    assert {:error, _} = PolicySaga.execute(saga, %{})
    assert {:comp_ctx, %{reservation_id: "abc"}} in Recorder.events()
  end

  test "invalid on_error policy raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      PolicySaga.step(PolicySaga.new(), :a, fn _ -> {:ok, 1} end, fn _ -> :ok end,
        on_error: :explode
      )
    end
  end

  test "empty saga returns the context unchanged" do
    assert {:ok, %{x: 1}} = PolicySaga.execute(PolicySaga.new(), %{x: 1})
    assert Recorder.events() == []
  end

  test "omitting :on_error defaults to :continue past a failed compensation" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a, {:ok, :undo_a}))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed}))
      |> PolicySaga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}
    assert err.aborted_at == nil
    assert err.uncompensated == []
    assert Recorder.comps() == [{:comp, :b}, {:comp, :a}]
  end

  test "error value carries exactly the documented key set" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, fail_action(:b, :boom), comp(:b))

    assert {:error, err} = PolicySaga.execute(saga, %{})

    assert err |> Map.keys() |> Enum.sort() ==
             [:aborted_at, :compensated, :compensations, :error, :step, :uncompensated]
  end

  test "actions after the failing step never run" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, fail_action(:b, :boom), comp(:b))
      |> PolicySaga.step(:c, ok_action(:c, 3), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.step == :b
    refute {:action, :c} in Recorder.events()
    refute {:comp, :c} in Recorder.events()
    assert Recorder.events() == [{:action, :a}, {:action, :b}, {:comp, :a}]
  end

  test "an earlier step's compensation sees later steps' stored results" do
    capture = fn name ->
      fn ctx ->
        Recorder.record({:comp_ctx, name, ctx})
        {:ok, :undone}
      end
    end

    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), capture.(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), capture.(:b))
      |> PolicySaga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, _} = PolicySaga.execute(saga, %{seed: :s})

    ctxs =
      for {:comp_ctx, name, ctx} <- Recorder.events(), into: %{}, do: {name, ctx}

    assert ctxs[:a] == %{seed: :s, a: 1, b: 2}
    assert ctxs[:b] == %{seed: :s, a: 1, b: 2}
  end

  test "uncompensated lists every skipped step in reverse completion order" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b))
      |> PolicySaga.step(:c, ok_action(:c, 3), comp(:c, {:error, :undo_failed}), on_error: :abort)
      |> PolicySaga.step(:d, fail_action(:d, :boom), comp(:d))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:c]
    assert err.aborted_at == :c
    assert err.uncompensated == [:b, :a]
    assert Recorder.comps() == [{:comp, :c}]
  end

  test "abort on the last compensation leaves nothing uncompensated" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a, {:error, :undo_failed}), on_error: :abort)
      |> PolicySaga.step(:b, fail_action(:b, :boom), comp(:b))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:a]
    assert err.compensations == %{a: {:error, :undo_failed}}
    assert err.aborted_at == :a
    assert err.uncompensated == []
  end
end
