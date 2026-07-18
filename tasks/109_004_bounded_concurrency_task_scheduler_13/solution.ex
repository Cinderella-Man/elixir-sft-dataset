  defp build_dependents(tasks) do
    Enum.reduce(tasks, %{}, fn {id, %{depends_on: deps}}, acc ->
      Enum.reduce(Enum.uniq(deps), acc, fn dep, acc2 ->
        Map.update(acc2, dep, [id], &[id | &1])
      end)
    end)
  end