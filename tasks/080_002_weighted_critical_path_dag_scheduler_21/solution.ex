  @doc """
  Adds a dependency edge meaning "`from` must finish before `to` starts".

  Both tasks must already exist.  Returns `{:ok, new_dag}` on success,
  `{:error, :task_not_found}` if either task is missing, or `{:error, :cycle}`
  if the edge would introduce a cycle (detected eagerly via DFS).
  """
  @spec add_dependency(t(), id(), id()) :: {:ok, t()} | {:error, :cycle | :task_not_found}
  def add_dependency(%__MODULE__{} = dag, from, to) do
    with :ok <- require_task(dag, from),
         :ok <- require_task(dag, to),
         :ok <- check_no_cycle(dag, from, to) do
      new_dag = %{
        dag
        | out_edges: Map.update!(dag.out_edges, from, &MapSet.put(&1, to)),
          in_edges: Map.update!(dag.in_edges, to, &MapSet.put(&1, from))
      }

      {:ok, new_dag}
    end
  end