# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule Saga do
  defstruct steps: []

  def new, do: %__MODULE__{steps: []}

  def step(%__MODULE__{steps: steps} = saga, name, action, compensation)
      when is_function(action, 1) and is_function(compensation, 1) do
    %__MODULE__{
      saga
      | steps: steps ++ [%{name: name, action: action, compensation: compensation}]
    }
  end

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
