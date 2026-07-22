# Implement `run_stages/4`

Implement the private, recursive `run_stages/4` function — the engine that drives the
`ParallelSaga` coordinator. It has the signature `run_stages(stages, idx, context, completed)`:

- `stages` — the remaining stages to run, each a list of step maps
  (`%{name:, action:, compensation:}`).
- `idx` — the 0-based index of the current (head) stage.
- `context` — the accumulated context map as it stands at the start of the current stage.
- `completed` — every step already successfully run in *earlier* stages, held as step maps
  in **reverse completion order** (most recent first), ready for compensation.

Behaviour:

- **Base case** (no stages left): return `{:ok, context}`.
- **Recursive case** (a `stage` at the head, followed by `rest`):
  1. Start **all** of the stage's actions concurrently with `Task.async/1`, each action
     receiving the **same** start-of-stage `context`. Then `Task.await/2` each task using
     the `@await_timeout`. Keep each step paired with its result.
  2. Collect the **failures**: a map `name => reason` for every step whose action returned
     `{:error, reason}`.
  3. **If there are no failures:** merge every step's `{:ok, result}` into the context under
     the step's `name` key to form the new context. Then recurse into `rest` with `idx + 1`,
     the new context, and an updated `completed` list — this stage's steps (in reverse of
     their declared order) prepended to the existing `completed`.
  4. **If there is at least one failure:** the stage fails. Build the compensation context by
     merging only the **succeeded** steps' results into `context` (failed steps contribute
     nothing). Determine the steps to compensate: the succeeded steps of the failing stage in
     reverse declared order, followed by everything in `completed`. Hand that list, the
     compensation context, the current `idx`, and the `failures` map to `compensate/4`, and
     return its result.

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

  defp run_stages([], _idx, context, _completed) do
    # TODO
  end

  defp compensate(to_compensate, context, stage_idx, failures) do
    {compensated, compensations} =
      Enum.reduce(to_compensate, {[], %{}}, fn
        %{name: name, compensation: comp}, {names, results} ->
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