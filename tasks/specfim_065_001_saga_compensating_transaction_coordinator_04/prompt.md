# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`execute/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `execute/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `execute/2` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
