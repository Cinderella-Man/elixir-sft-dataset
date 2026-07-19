# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `step` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Policy-Driven Saga / Compensating Transaction Coordinator

Write me an Elixir module called `PolicySaga` that executes a **saga** — a sequence of
steps, each with a forward **action** and a **compensating action** — with a
configurable **rollback policy** per step. As in a normal saga, if a step's action
fails, the coordinator runs the compensations of previously-completed steps in reverse
order. The twist: a step can declare that if **its own compensation fails**, the whole
rollback must **abort** (stop immediately, leaving the remaining earlier steps
uncompensated for manual intervention) rather than continuing best-effort.

Use only the Elixir/OTP standard library — no external dependencies. Give me the
complete module in a single file.

## Public API

```elixir
PolicySaga.new()
|> PolicySaga.step(:reserve, &reserve/1, &cancel/1, on_error: :abort)
|> PolicySaga.step(:charge,  &charge/1,  &refund/1)
|> PolicySaga.execute(%{order_id: 42})
```

### `PolicySaga.new/0`

Returns a new, empty saga value (opaque).

### `PolicySaga.step(saga, name, action, compensation, opts \\ [])`

Appends a step and returns the updated saga.

- `name` — an identifier for the step.
- `action` — a 1-arity function receiving the current **context** (a map), returning
  `{:ok, result}` or `{:error, reason}`.
- `compensation` — a 1-arity function receiving the context that undoes the step; its
  return value is recorded. By convention it returns `{:ok, _}` (success) or
  `{:error, _}` (failed to compensate).
- `opts` — supports `:on_error`, the step's rollback policy, one of:
  - `:continue` (default) — if this step's compensation returns `{:error, _}`, record
    it and keep running the remaining compensations (best-effort).
  - `:abort` — if this step's compensation returns `{:error, _}`, stop the whole
    rollback immediately; earlier steps are left uncompensated.

Any other `:on_error` value must raise `ArgumentError`. Steps run in the order added.

### `PolicySaga.execute(saga, context)`

**Forward pass.** For each step in order, call its `action`:

- On `{:ok, result}`: store under the step's `name` key, mark the step **completed**,
  continue.
- On `{:error, reason}`: stop the forward pass and begin compensation.

**Compensation pass.** Run the compensations of the completed steps in reverse
completion order (most recently completed first). Each compensation receives the
context accumulated up to the point of failure. For each compensation that returns
`{:error, _}`: if that step's policy is `:abort`, stop the pass immediately (the
compensations *not yet run* are left uncompensated); otherwise record and continue.
The failed step's compensation is not run.

### Return values

- **All steps succeed:** `{:ok, final_context}`.
- **A step fails:** `{:error, error}` where `error` has exactly these keys:
  - `:step` — the `name` of the failing step.
  - `:error` — the `reason` from the failing action.
  - `:compensated` — the list of step names whose compensations ran (were attempted),
    in run order.
  - `:compensations` — a map `name => compensation_return_value`.
  - `:aborted_at` — the `name` of the compensation whose failure aborted the rollback,
    or `nil` if the pass completed normally.
  - `:uncompensated` — the list of completed step names that were *not* compensated
    because the rollback aborted, in the order they would have run (`[]` if none).
- **Empty saga:** `{:ok, context}` unchanged.

## The module with `step` missing

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

  def step(%__MODULE__{steps: steps} = saga, name, action, compensation, opts \\ [])
      when is_function(action, 1) and is_function(compensation, 1) do
    # TODO
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

Give me only the complete implementation of `step` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
