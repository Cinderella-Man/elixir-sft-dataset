  def add_edge(%__MODULE__{} = dag, from, to) do
    with :ok <- require_vertex(dag, from),
         :ok <- require_vertex(dag, to) do
      cond do
        from == to ->
          {:error, {:cycle, [from, from]}}

        true ->
          # Adding from->to closes a cycle iff `from` is already reachable
          # from `to`. reach_path returns [to, ..., from] when such a path
          # exists; prefixing `from` yields the full loop [from, to, ..., from].
          case reach_path(dag.out_edges, to, from) do
            nil ->
              new_dag = %{
                dag
                | out_edges: Map.update!(dag.out_edges, from, &MapSet.put(&1, to)),
                  in_edges: Map.update!(dag.in_edges, to, &MapSet.put(&1, from))
              }

              {:ok, new_dag}

            path ->
              {:error, {:cycle, [from | path]}}
          end
      end
    end
  end