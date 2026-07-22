  defp dfs(id, children_map, colors, stack) do
    colors = Map.put(colors, id, :grey)
    stack = [id | stack]

    child_ids = Map.get(children_map, id, [])

    result =
      Enum.reduce_while(child_ids, {:ok, colors}, fn child_id, {:ok, acc_colors} ->
        case Map.get(acc_colors, child_id) do
          :grey ->
            # Back-edge → cycle found.
            # Extract the cycle portion from the stack.
            cycle = extract_cycle(child_id, [child_id | stack])
            {:halt, {:error, {:cycle_detected, cycle}}}

          :white ->
            case dfs(child_id, children_map, acc_colors, stack) do
              {:ok, new_colors} -> {:cont, {:ok, new_colors}}
              {:error, _} = err -> {:halt, err}
            end

          :black ->
            # Already fully explored; safe to skip.
            {:cont, {:ok, acc_colors}}

          nil ->
            # child_id not in our color map → orphan reference, skip.
            {:cont, {:ok, acc_colors}}
        end
      end)

    case result do
      {:ok, colors} ->
        {:ok, Map.put(colors, id, :black)}

      {:error, _} = err ->
        err
    end
  end