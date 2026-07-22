  defp reaches?(table, from, target, visited) do
    cond do
      from == target ->
        true

      MapSet.member?(visited, from) ->
        false

      true ->
        visited = MapSet.put(visited, from)

        Enum.any?(existing_prereqs(table, from), fn n ->
          reaches?(table, n, target, visited)
        end)
    end
  end