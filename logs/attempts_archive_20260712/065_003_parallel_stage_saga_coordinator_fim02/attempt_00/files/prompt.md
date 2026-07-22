# Implement `compensate/4`

Implement the private `compensate/4` function. It is the final step of a failed
saga run and is responsible for undoing already-completed work and building the
error result.

It receives four arguments:

- `to_compensate` — a list of step maps (each with `:name` and `:compensation`)
  **already in the exact order they must be run**: the succeeded steps of the
  failing stage in reverse declared order, followed by every earlier stage
  (most recent first, each stage's steps in reverse declared order).
- `context` — the context accumulated up to the point of failure (including the
  failing stage's succeeded results). Every compensation receives this same map.
- `stage_idx` — the 0-based index of the stage that failed.
- `failures` — a map `name => reason` for every step in the failing stage whose
  action returned `{:error, _}`.

It must, in order, run each step's compensation function on `context`
(best-effort: a compensation's return value is recorded but never stops the
pass), while accumulating two things:

- the list of step names whose compensations ran, in **run order**; and
- a map `name => compensation_return_value`.

Finally it returns `{:error, error}` where `error` is a map with exactly these
keys:

- `:stage` — `stage_idx`.
- `:failed` — `failures`.
- `:compensated` — the list of compensated step names in run order.
- `:compensations` — the map of `name => compensation_return_value`.

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
    # TODO
  end
end
```