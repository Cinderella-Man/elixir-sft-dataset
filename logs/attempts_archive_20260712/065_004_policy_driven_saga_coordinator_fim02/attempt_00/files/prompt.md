# Implement `forward/3`

Implement the private `forward/3` function, which drives the saga's **forward pass**.

`forward/3` receives three arguments:

1. the remaining list of steps to run, in order;
2. the current **context** (a map that accumulates each successful step's result under
   that step's `name` key); and
3. the `completed` list — the steps that have already succeeded, held in **reverse
   completion order** (most recently completed step first).

It must behave as follows:

- **Base case (no steps left):** the forward pass finished with every step succeeding,
  so return `{:ok, context}`.
- **Recursive case:** run the head step's `action` on the current `context`.
  - On `{:ok, result}`: store `result` in the context under the step's `name`, prepend
    the step onto `completed` (keeping it in reverse completion order), and recurse on
    the remaining steps.
  - On `{:error, reason}`: stop the forward pass and begin compensation by calling
    `compensate/4` with the `completed` steps, the current `context`, the failing
    step's `name`, and the `reason`.

Here is the whole module, with only the body of `forward/3` left as `# TODO`:

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
  @spec step(t(), term(), (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term()), keyword()) :: t()
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
  defp forward(steps, context, completed) do
    # TODO
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