# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

# Parallel-Stage Saga / Compensating Transaction Coordinator

Write me an Elixir module called `ParallelSaga` that executes a **staged saga**. The
saga is built from a series of **stages**; each stage contains one or more steps, and
all steps **within a stage run concurrently**. Every step has a forward **action** and
a **compensating action**. If any step in a stage fails, the coordinator undoes the
work already done — the succeeded steps of the failing stage plus every step of all
earlier stages — by running their compensating actions, and returns an error.

Use only the Elixir/OTP standard library (`Task` is allowed) — no external
dependencies. Give me the complete module in a single file.

## Public API

```elixir
ParallelSaga.new()
|> ParallelSaga.stage([
     {:reserve, &reserve/1, &cancel/1},
     {:notify,  &notify/1,  &unnotify/1}
   ])
|> ParallelSaga.stage([
     {:charge, &charge/1, &refund/1}
   ])
|> ParallelSaga.execute(%{order_id: 42})
```

### `ParallelSaga.new/0`

Returns a new, empty saga value (opaque).

### `ParallelSaga.stage(saga, steps)`

Appends a stage and returns the updated saga. `steps` is a list of
`{name, action, compensation}` tuples:

- `name` — an identifier for the step.
- `action` — a 1-arity function receiving the current **context** (a map), returning
  `{:ok, result}` or `{:error, reason}`.
- `compensation` — a 1-arity function receiving the context that undoes the step.

`action` and `compensation` must both be arity-1 functions, otherwise raise
`ArgumentError`. Stages run in the order added.

### `ParallelSaga.execute(saga, context)`

For each stage in order:

- Start **all** of the stage's actions concurrently, each receiving the **same**
  context — the context as it was at the start of the stage. (Steps in the same stage
  therefore cannot see each other's results; only later stages see a stage's results.)
- Await all actions.
  - If every action returns `{:ok, result}`: merge each result into the context under
    its `name` key and proceed to the next stage.
  - If **any** action returns `{:error, reason}`: the stage fails. Begin compensation.

**Compensation pass.** Run the compensations of every step that must be undone, in
this order: first the **succeeded** steps of the failing stage (in reverse of their
declared order within the stage), then every earlier stage (most recent stage first,
each stage's steps in reverse declared order). The failed step(s) are *not* compensated
(their actions did not succeed). Each compensation receives the context accumulated up
to the point of failure (including the failing stage's succeeded results). Compensation
is best-effort: errors are recorded but do not stop the pass.

### Return values

- **All stages succeed:** `{:ok, final_context}`.
- **A stage fails:** `{:error, error}` where `error` has exactly these keys:
  - `:stage` — the 0-based index of the failing stage.
  - `:failed` — a map `name => reason` for every step in that stage whose action
    returned `{:error, _}` (there may be more than one).
  - `:compensated` — the list of step names whose compensations ran, in run order.
  - `:compensations` — a map `name => compensation_return_value`.
- **Empty saga:** `{:ok, context}` unchanged.

## Module under test

```elixir
defmodule ParallelSaga do
  @moduledoc """
  A staged saga / compensating-transaction coordinator.

  The saga is a list of stages; the steps within a stage run **concurrently**, each
  receiving the same start-of-stage context. If any step in a stage fails, the
  succeeded steps of that stage plus all earlier stages are compensated (best-effort)
  in reverse completion order.
  """

  @opaque t :: %__MODULE__{stages: [[step()]]}
  @type context :: map()
  @type step :: %{
          name: term(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensation: (context() -> term())
        }
  @type error :: %{
          stage: non_neg_integer(),
          failed: %{optional(term()) => term()},
          compensated: [term()],
          compensations: %{optional(term()) => term()}
        }

  @await_timeout 5_000

  defstruct stages: []

  @doc "Returns a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc "Appends a stage of `{name, action, compensation}` tuples."
  @spec stage(t(), [{term(), function(), function()}]) :: t()
  def stage(%__MODULE__{stages: stages} = saga, steps) when is_list(steps) do
    normalized =
      Enum.map(steps, fn {name, action, compensation} ->
        unless is_function(action, 1) and is_function(compensation, 1) do
          raise ArgumentError, "action and compensation must be arity-1 functions"
        end

        %{name: name, action: action, compensation: compensation}
      end)

    %__MODULE__{saga | stages: stages ++ [normalized]}
  end

  @doc "Runs the saga from `context`."
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{stages: stages}, context) when is_map(context) do
    run_stages(stages, 0, context, [])
  end

  # `completed` holds step maps in reverse completion order (most recent first).
  defp run_stages([], _idx, context, _completed), do: {:ok, context}

  defp run_stages([stage | rest], idx, context, completed) do
    results =
      stage
      |> Enum.map(fn step -> {step, Task.async(fn -> step.action.(context) end)} end)
      |> Enum.map(fn {step, task} -> {step, Task.await(task, @await_timeout)} end)

    failures = for {step, {:error, reason}} <- results, into: %{}, do: {step.name, reason}

    if map_size(failures) == 0 do
      new_context =
        Enum.reduce(results, context, fn {step, {:ok, result}}, acc ->
          Map.put(acc, step.name, result)
        end)

      succeeded = Enum.map(results, fn {step, _} -> step end)
      run_stages(rest, idx + 1, new_context, Enum.reverse(succeeded) ++ completed)
    else
      succeeded = for {step, {:ok, _}} <- results, do: step

      comp_context =
        Enum.reduce(results, context, fn
          {step, {:ok, result}}, acc -> Map.put(acc, step.name, result)
          {_step, {:error, _}}, acc -> acc
        end)

      to_compensate = Enum.reverse(succeeded) ++ completed
      compensate(to_compensate, comp_context, idx, failures)
    end
  end

  defp compensate(to_compensate, context, stage_idx, failures) do
    {compensated, compensations} =
      Enum.reduce(to_compensate, {[], %{}}, fn %{name: name, compensation: comp}, {names, results} ->
        result = comp.(context)
        {[name | names], Map.put(results, name, result)}
      end)

    {:error,
     %{
       stage: stage_idx,
       failed: failures,
       compensated: Enum.reverse(compensated),
       compensations: compensations
     }}
  end
end
```
