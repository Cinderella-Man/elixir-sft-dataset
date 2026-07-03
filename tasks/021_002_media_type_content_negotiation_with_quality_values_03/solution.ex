defp best_version([]), do: nil

defp best_version(list) do
  {{v, _q}, _idx} =
    list
    |> Enum.with_index()
    |> Enum.max_by(fn {{_v, q}, idx} -> {q, -idx} end)

  v
end