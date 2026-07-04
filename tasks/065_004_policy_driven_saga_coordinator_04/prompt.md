# Implement `compensate/4`

Implement the private `compensate/4` function. It is the entry point to the
**compensation pass**, called when a step's forward action returns
`{:error, reason}`. Its arguments are:

- `completed` — the list of already-completed step maps, in **reverse completion
  order** (most recently completed first), i.e. the exact order their
  compensations should run.
- `context` — the context map accumulated up to the point of failure.
- `failed_step` — the `name` of the step whose action failed.
- `reason` — the `reason` returned by that failing action.

It should delegate the actual rollback to `do_compensate/4`, calling it with
`completed`, `context`, and empty accumulators (`[]` for the run list and `%{}`
for the compensation-results map). `do_compensate/4` returns a 4-tuple
`{ran, compensations, aborted_at, uncompensated}`, where `ran` is the list of
compensated step names in **reverse** run order.

`compensate/4` must then return `{:error, error}`, where `error` is a map with
exactly these keys:

- `:step` — `failed_step`.
- `:error` — `reason`.
- `:compensated` — the step names whose compensations ran, in **run order**
  (i.e. `ran` reversed).
- `:compensations` — the `compensations` map (`name => compensation_return_value`).
- `:aborted_at` — `aborted_at` (the step name whose compensation failure aborted
  the rollback, or `nil`).
- `:uncompensated` — `uncompensated` (completed step names skipped due to an
  abort, in the order they would have run; `[]` if none).

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
    # TODO
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