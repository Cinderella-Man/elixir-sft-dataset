  # Build a map of parent_id → [child_id, ...] in original order.
  @spec build_children_map([node_map()]) :: %{id() => [id()]}
  defp build_children_map(items) do
    # We want children in the same order as the original list, so we walk
    # forward and append (via reversal at the end).
    items
    |> Enum.reduce(%{}, fn item, acc ->
      pid = item.parent_id

      if is_nil(pid) do
        acc
      else
        Map.update(acc, pid, [item.id], fn existing -> existing ++ [item.id] end)
      end
    end)
  end