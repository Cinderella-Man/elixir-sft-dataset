# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule PolicySaga do
  defstruct steps: []

  def new, do: %__MODULE__{steps: []}

  def step(%__MODULE__{steps: steps} = saga, name, action, compensation, opts \\ [])
      when is_function(action, 1) and is_function(compensation, 1) do
    policy = Keyword.get(opts, :on_error, :continue)

    unless policy in [:continue, :abort] do
      raise ArgumentError, "on_error must be :continue or :abort, got: #{inspect(policy)}"
    end

    step = %{name: name, action: action, compensation: compensation, policy: policy}
    %__MODULE__{saga | steps: steps ++ [step]}
  end

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
