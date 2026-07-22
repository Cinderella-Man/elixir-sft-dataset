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