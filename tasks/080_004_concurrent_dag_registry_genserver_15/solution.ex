  defp require_vertex(state, vertex) do
    if MapSet.member?(state.vertices, vertex), do: :ok, else: {:error, :vertex_not_found}
  end