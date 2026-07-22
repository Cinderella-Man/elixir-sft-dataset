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