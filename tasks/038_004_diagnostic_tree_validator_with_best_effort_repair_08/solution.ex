  defp do_extract(items, acc) do
    ordered_ids = Enum.map(items, & &1.id)
    children_map = build_children_map(items)

    case detect_cycle(ordered_ids, children_map) do
      :ok ->
        {Enum.reverse(acc), items}

      {:error, {:cycle_detected, cycle_ids}} ->
        cycle_set = MapSet.new(cycle_ids)
        remaining = Enum.reject(items, fn item -> MapSet.member?(cycle_set, item.id) end)
        do_extract(remaining, [cycle_ids | acc])
    end
  end