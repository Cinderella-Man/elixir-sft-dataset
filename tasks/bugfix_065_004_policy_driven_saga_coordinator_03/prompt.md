# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

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

## The buggy module

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

      {:ok, reason} ->
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

## Failing test report

```
6 of 9 test(s) failed:

  * test failure with all compensations succeeding: no abort
      no case clause matching:
      
          {:error, :boom}
      

  * test :continue policy keeps rolling back past a failed compensation
      no case clause matching:
      
          {:error, :nope}
      

  * test :abort policy stops the rollback and leaves earlier steps uncompensated
      no case clause matching:
      
          {:error, :fail}
      

  * test :abort policy does not fire when that step's compensation succeeds
      no case clause matching:
      
          {:error, :boom}
      

  (…2 more)
```
