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