  defp schedule(tasks, max) when map_size(tasks) == 0 and max > 0, do: %{}

  defp schedule(tasks, max) do
    in_degree =
      Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, length(Enum.uniq(deps))} end)

    dependents = build_dependents(tasks)
    ready = for {id, 0} <- in_degree, do: id

    loop(%{
      tasks: tasks,
      max: max,
      in_degree: in_degree,
      dependents: dependents,
      ready: ready,
      running: %{},
      results: %{}
    })
  end