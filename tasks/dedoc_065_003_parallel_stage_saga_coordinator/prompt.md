# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule ParallelSaga do
  @await_timeout 5_000

  defstruct stages: []

  def new, do: %__MODULE__{stages: []}

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
