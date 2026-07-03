  defp requestable do
    @statuses
    |> Enum.filter(fn {_v, status} -> status in [:active, :deprecated] end)
    |> Enum.map(fn {v, _status} -> v end)
    |> Enum.sort()
  end