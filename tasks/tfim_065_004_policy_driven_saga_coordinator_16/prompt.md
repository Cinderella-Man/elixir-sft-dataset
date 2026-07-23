# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule PolicySaga do
  @moduledoc """
  A saga / compensating-transaction coordinator with a per-step **rollback policy**.

  Steps run in order; on a step failure the compensations of previously-completed
  steps run in reverse completion order. A step's `:on_error` policy governs what
  happens if *its own compensation* returns `{:error, _}`:

    * `:continue` (default) — record and keep rolling back (best-effort).
    * `:abort` — stop the rollback immediately; earlier steps are left uncompensated.
  """

  @opaque t :: %__MODULE__{steps: [step()]}
  @type context :: map()
  @type policy :: :continue | :abort
  @type step :: %{
          name: term(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensation: (context() -> term()),
          policy: policy()
        }
  @type error :: %{
          step: term(),
          error: term(),
          compensated: [term()],
          compensations: %{optional(term()) => term()},
          aborted_at: term() | nil,
          uncompensated: [term()]
        }

  defstruct steps: []

  @doc "Returns a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{steps: []}

  @doc """
  Appends a step. `opts` supports `:on_error` (`:continue` default, or `:abort`).
  """
  @spec step(
          t(),
          term(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term()),
          keyword()
        ) :: t()
  def step(%__MODULE__{steps: steps} = saga, name, action, compensation, opts \\ [])
      when is_function(action, 1) and is_function(compensation, 1) do
    policy = Keyword.get(opts, :on_error, :continue)

    unless policy in [:continue, :abort] do
      raise ArgumentError, "on_error must be :continue or :abort, got: #{inspect(policy)}"
    end

    step = %{name: name, action: action, compensation: compensation, policy: policy}
    %__MODULE__{saga | steps: steps ++ [step]}
  end

  @doc "Runs the saga from `context`."
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    forward(steps, context, [])
  end

  # `completed` is in reverse completion order (most recent first).
  defp forward([], context, _completed), do: {:ok, context}

  defp forward([step | rest], context, completed) do
    case step.action.(context) do
      {:ok, result} ->
        forward(rest, Map.put(context, step.name, result), [step | completed])

      {:error, reason} ->
        compensate(completed, context, step.name, reason)
    end
  end

  defp compensate(completed, context, failed_step, reason) do
    {ran, compensations, aborted_at, uncompensated} =
      do_compensate(completed, context, [], %{})

    {:error,
     %{
       step: failed_step,
       error: reason,
       compensated: Enum.reverse(ran),
       compensations: compensations,
       aborted_at: aborted_at,
       uncompensated: uncompensated
     }}
  end

  # Returns {ran (reverse run order), compensations, aborted_at, uncompensated}.
  defp do_compensate([], _context, ran, results), do: {ran, results, nil, []}

  defp do_compensate([step | rest], context, ran, results) do
    result = step.compensation.(context)
    ran = [step.name | ran]
    results = Map.put(results, step.name, result)

    case result do
      {:error, _} when step.policy == :abort ->
        {ran, results, step.name, Enum.map(rest, & &1.name)}

      _ ->
        do_compensate(rest, context, ran, results)
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
  end
end
```
