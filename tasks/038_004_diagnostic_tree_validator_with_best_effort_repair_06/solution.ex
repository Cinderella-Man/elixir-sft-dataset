  defp normalize(items) do
    {normed, missing} =
      Enum.map_reduce(items, [], fn item, missing ->
        if Map.has_key?(item, :parent_id) do
          {item, missing}
        else
          {Map.put(item, :parent_id, nil), [item.id | missing]}
        end
      end)

    {normed, Enum.reverse(missing)}
  end