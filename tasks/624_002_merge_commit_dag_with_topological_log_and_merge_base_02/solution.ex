  @spec lowest_common(map(), MapSet.t()) :: MapSet.t()
  defp lowest_common(objects, common) do
    proper =
      Enum.reduce(common, MapSet.new(), fn node, acc ->
        node_ancestors =
          objects
          |> ancestors(node)
          |> MapSet.delete(node)

        MapSet.union(acc, MapSet.intersection(node_ancestors, common))
      end)

    MapSet.difference(common, proper)
  end