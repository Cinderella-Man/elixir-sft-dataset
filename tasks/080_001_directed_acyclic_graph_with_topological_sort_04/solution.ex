  @spec add_edge(t(), vertex(), vertex()) :: {:ok, t()} | {:error, :cycle | :vertex_not_found}
  def add_edge(%__MODULE__{} = dag, from, to) do
    with :ok <- require_vertex(dag, from),
         :ok <- require_vertex(dag, to),
         :ok <- check_no_cycle(dag, from, to) do
      new_dag = %{
        dag
        | out_edges: Map.update!(dag.out_edges, from, &MapSet.put(&1, to)),
          in_edges: Map.update!(dag.in_edges, to, &MapSet.put(&1, from))
      }

      {:ok, new_dag}
    end
  end