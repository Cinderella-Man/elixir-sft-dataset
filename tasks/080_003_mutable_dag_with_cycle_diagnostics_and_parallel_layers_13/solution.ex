  defp require_vertex(dag, vertex) do
    if MapSet.member?(dag.vertices, vertex), do: :ok, else: {:error, :vertex_not_found}
  end