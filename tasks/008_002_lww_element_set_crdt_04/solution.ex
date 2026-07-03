  @spec compute_members(lww_state()) :: MapSet.t()
  defp compute_members(%{adds: adds, removes: removes}) do
    adds
    |> Enum.filter(fn {element, add_ts} ->
      remove_ts = Map.get(removes, element, 0)
      add_ts > remove_ts
    end)
    |> Enum.map(fn {element, _ts} -> element end)
    |> MapSet.new()
  end