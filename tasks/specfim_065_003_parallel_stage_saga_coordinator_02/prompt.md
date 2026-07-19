# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`new/0` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `new/0`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `new/0` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
