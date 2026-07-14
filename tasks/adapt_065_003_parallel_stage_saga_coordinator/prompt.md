# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Saga do
  @moduledoc """
  A saga / compensating-transaction coordinator.

  A saga is a sequence of steps, each with a forward *action* and a
  *compensating action*. Steps are executed in the order they were added. If any
  step's action fails, the coordinator undoes the work already performed by
  running the compensating actions of all previously-completed steps, in reverse
  completion order.

  ## Example

      Saga.new()
      |> Saga.step(:reserve, &reserve/1, &cancel_reservation/1)
      |> Saga.step(:charge,  &charge/1,  &refund/1)
      |> Saga.step(:ship,    &ship/1,    &unship/1)
      |> Saga.execute(%{order_id: 42})

  """

  @typedoc "An opaque saga value."
  @opaque t :: %__MODULE__{steps: [step()]}

  @typedoc "The context passed between steps."
  @type context :: map()

  @typedoc "An individual step in the saga."
  @type step :: %{
          name: term(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensation: (context() -> term())
        }

  @typedoc "The error map returned when a step fails."
  @type error :: %{
          step: term(),
          error: term(),
          compensated: [term()],
          compensations: %{optional(term()) => term()}
        }

  defstruct steps: []

  @doc """
  Returns a new, empty saga.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{steps: []}

  @doc """
  Appends a step to the saga and returns the updated saga.

  Steps run in the order they were added.

    * `name` — an identifier for the step (typically an atom).
    * `action` — a 1-arity function receiving the current context; must return
      `{:ok, result}` or `{:error, reason}`.
    * `compensation` — a 1-arity function receiving the current context that
      undoes the step's effect. Its return value is recorded.
  """
  @spec step(
          t(),
          term(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term())
        ) ::
          t()
  def step(%__MODULE__{steps: steps} = saga, name, action, compensation)
      when is_function(action, 1) and is_function(compensation, 1) do
    %__MODULE__{
      saga
      | steps: steps ++ [%{name: name, action: action, compensation: compensation}]
    }
  end

  @doc """
  Runs the saga starting from the given `context` map.

  Returns `{:ok, final_context}` if every step succeeds, or `{:error, error}`
  (see `t:error/0`) if a step's action fails, after best-effort compensation of
  the previously-completed steps.
  """
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    forward(steps, context, [])
  end

  # Forward pass: execute each remaining step's action in order.
  #
  # `completed` accumulates the completed steps in reverse completion order
  # (most-recently-completed first), which is exactly the order needed for the
  # compensation pass.
  defp forward([], context, _completed), do: {:ok, context}

  defp forward([%{name: name, action: action} = step | rest], context, completed) do
    case action.(context) do
      {:ok, result} ->
        new_context = Map.put(context, name, result)
        forward(rest, new_context, [step | completed])

      {:error, reason} ->
        compensate(completed, context, name, reason)
    end
  end

  # Compensation pass: run each completed step's compensation in reverse
  # completion order (best-effort — errors are recorded but do not stop the pass).
  defp compensate(completed, context, failed_step, reason) do
    {compensated, compensations} =
      Enum.reduce(completed, {[], %{}}, fn %{name: name, compensation: compensation},
                                           {names, results} ->
        result = compensation.(context)
        {[name | names], Map.put(results, name, result)}
      end)

    {:error,
     %{
       step: failed_step,
       error: reason,
       compensated: Enum.reverse(compensated),
       compensations: compensations
     }}
  end
end
```

## New specification

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
