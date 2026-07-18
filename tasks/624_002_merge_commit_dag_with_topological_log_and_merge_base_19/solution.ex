  @spec ancestors(map(), hash()) :: MapSet.t()
  defp ancestors(objects, start) do
    ancestors_walk([start], objects, MapSet.new())
  end