  @doc """
  Adds a task vertex `id` with a non-negative numeric `duration`.

  If the task already exists the dag is returned unchanged, keeping the
  original duration.
  """
  @spec add_task(t(), id(), number()) :: t()
  def add_task(%__MODULE__{} = dag, id, duration)
      when is_number(duration) and duration >= 0 do
    if Map.has_key?(dag.durations, id) do
      dag
    else
      %{
        dag
        | durations: Map.put(dag.durations, id, duration),
          out_edges: Map.put_new(dag.out_edges, id, MapSet.new()),
          in_edges: Map.put_new(dag.in_edges, id, MapSet.new())
      }
    end
  end