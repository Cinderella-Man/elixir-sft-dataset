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
defmodule RetrySaga do
  defstruct steps: []

  def new, do: %__MODULE__{steps: []}

  def step(%__MODULE__{steps: steps} = saga, name, action, compensation, opts \\ [])
      when is_function(action, 1) and is_function(compensation, 1) do
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    unless is_integer(max_attempts) and max_attempts >= 1 do
      raise ArgumentError,
            "max_attempts must be a positive integer, got: #{inspect(max_attempts)}"
    end

    step = %{name: name, action: action, compensation: compensation, max_attempts: max_attempts}
    %__MODULE__{saga | steps: steps ++ [step]}
  end

  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    forward(steps, context, [])
  end

  # `completed` is in reverse completion order (most recent first).
  defp forward([], context, _completed), do: {:ok, context}

  defp forward([step | rest], context, completed) do
    case run_action(step, context, 1) do
      {:ok, result} ->
        forward(rest, Map.put(context, step.name, result), [step | completed])

      {:error, reason, attempts} ->
        compensate(completed, context, step.name, reason, attempts)
    end
  end

  defp run_action(step, context, attempt) do
    case step.action.(context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if attempt < step.max_attempts do
          run_action(step, context, attempt + 1)
        else
          {:error, reason, attempt}
        end
    end
  end

  defp compensate(completed, context, failed_step, reason, attempts) do
    {compensated, compensations} =
      Enum.reduce(completed, {[], %{}}, fn %{name: name, compensation: comp}, {names, results} ->
        result = comp.(context)
        {[name | names], Map.put(results, name, result)}
      end)

    {:error,
     %{
       step: failed_step,
       error: reason,
       attempts: attempts,
       compensated: Enum.reverse(compensated),
       compensations: compensations
     }}
  end
end
```
