  defp backtrack(dag, est, current, acc) do
    start = Map.fetch!(est, current)

    candidates =
      dag.in_edges
      |> Map.fetch!(current)
      |> Enum.filter(fn p -> Map.fetch!(est, p) + Map.fetch!(dag.durations, p) == start end)
      |> Enum.sort()

    case candidates do
      [] -> acc
      [p | _] -> backtrack(dag, est, p, [p | acc])
    end
  end