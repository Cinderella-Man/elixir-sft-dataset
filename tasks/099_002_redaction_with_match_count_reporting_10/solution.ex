  @spec walk_map(t(), map()) :: {map(), report()}
  defp walk_map(redactor, map) do
    Enum.reduce(map, {%{}, @empty_report}, fn {k, v}, {acc, rep} ->
      {new_v, new_rep} = redact_pair(redactor, k, v)
      {Map.put(acc, k, new_v), merge(rep, new_rep)}
    end)
  end