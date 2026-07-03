  @spec compute_members(or_state()) :: MapSet.t()
  defp compute_members(%{entries: entries}) do
    entries
    |> Enum.filter(fn {_elem, tags} -> MapSet.size(tags) > 0 end)
    |> Enum.map(fn {elem, _tags} -> elem end)
    |> MapSet.new()
  end