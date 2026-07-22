  defp kahn([], in_degree, _out_edges, acc), do: {Enum.reverse(acc), in_degree}

  defp kahn([v | rest], in_degree, out_edges, acc) do
    # Decrement in-degree for every successor of v
    {new_in_degree, newly_zero} =
      out_edges
      |> Map.fetch!(v)
      |> Enum.reduce({in_degree, []}, fn succ, {deg_map, zeros} ->
        new_deg = Map.fetch!(deg_map, succ) - 1
        updated = Map.put(deg_map, succ, new_deg)

        if new_deg == 0 do
          {updated, [succ | zeros]}
        else
          {updated, zeros}
        end
      end)

    # Append newly-zero vertices in sorted order for determinism
    new_queue = rest ++ Enum.sort(newly_zero)

    kahn(new_queue, new_in_degree, out_edges, [v | acc])
  end