# Implement `forward/3`

Implement the private `forward/3` function, which drives the saga's **forward
pass**. It is the recursive worker behind `execute/2` and is called as
`forward(steps, context, completed)` where:

- `steps` is the list of not-yet-run steps (each a map with `:name`, `:action`,
  and `:compensation`), in the order they should run;
- `context` is the current context map accumulated so far; and
- `completed` is the list of already-completed steps in **reverse** completion
  order (most-recently-completed first) — exactly the order the compensation
  pass needs.

Behavior:

- **Base case** — when there are no remaining steps, the whole saga succeeded:
  return `{:ok, context}`.
- **Recursive case** — take the first remaining step and call its `action` with
  the current `context`:
  - On `{:ok, result}`: store the result in the context under the step's `name`
    key (`Map.put(context, name, result)`), prepend the step onto `completed`,
    and recurse on the rest of the steps with the updated context. Later steps
    therefore see earlier steps' results.
  - On `{:error, reason}`: stop the forward pass immediately (run no further
    actions) and begin the compensation pass by delegating to
    `compensate/4`, passing the `completed` steps, the current `context`, the
    failing step's `name`, and the `reason`.

Provide the full definition of `forward/3` (all clauses).

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
  defp forward([], context, _completed) do
    # TODO
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