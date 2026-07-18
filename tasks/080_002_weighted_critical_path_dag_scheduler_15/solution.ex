  defp require_task(dag, id) do
    if Map.has_key?(dag.durations, id), do: :ok, else: {:error, :task_not_found}
  end