  # The tasks left over when Kahn's algorithm stalls include both the tasks on a
  # cycle and their downstream dependents. Repeatedly dropping tasks that nothing
  # in the remaining set depends on leaves only the tasks on a cycle.
  defp cycle_nodes(ids, dependents) do
    ids |> MapSet.new() |> prune_downstream(dependents)
  end